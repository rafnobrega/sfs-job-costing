public with sharing class RN_SFS_JobCostingController {

    @AuraEnabled(cacheable=true)
    public static ProfitabilityData getProfitability(Id workOrderId) {
        ProfitabilityData result = new ProfitabilityData();

        // 1. Query Work Order with WorkType info
        WorkOrder wo = [
            SELECT Id, WorkOrderNumber, WorkTypeId, Pricebook2Id,
                   WorkType.EstimatedDuration,
                   WorkType.DurationType
            FROM WorkOrder
            WHERE Id = :workOrderId
            WITH USER_MODE
            LIMIT 1
        ];

        // 2. Identify labor product(s) dynamically
        List<Product2> laborProducts = [
            SELECT Id FROM Product2
            WHERE Name = 'Labor' OR Family = 'Labor'
            WITH USER_MODE
        ];
        Set<Id> laborProductIds = new Set<Id>();
        for (Product2 p : laborProducts) {
            laborProductIds.add(p.Id);
        }

        // 3. Query ProductRequired — try WorkOrder first, fall back to WorkType
        List<ProductRequired> prodReqs = [
            SELECT Id, QuantityRequired, Product2Id
            FROM ProductRequired
            WHERE ParentRecordId = :workOrderId
            WITH USER_MODE
        ];
        if (prodReqs.isEmpty() && wo.WorkTypeId != null) {
            prodReqs = [
                SELECT Id, QuantityRequired, Product2Id
                FROM ProductRequired
                WHERE ParentRecordId = :wo.WorkTypeId
                WITH USER_MODE
            ];
        }

        // 4. Get unit prices from PricebookEntry
        Set<Id> productIds = new Set<Id>();
        for (ProductRequired pr : prodReqs) {
            if (pr.Product2Id != null) {
                productIds.add(pr.Product2Id);
            }
        }

        Map<Id, Decimal> priceByProductId = new Map<Id, Decimal>();
        if (!productIds.isEmpty()) {
            List<PricebookEntry> pbes;
            if (wo.Pricebook2Id != null) {
                pbes = [
                    SELECT Product2Id, UnitPrice
                    FROM PricebookEntry
                    WHERE Pricebook2Id = :wo.Pricebook2Id
                      AND Product2Id IN :productIds
                      AND IsActive = true
                    WITH USER_MODE
                ];
            } else {
                pbes = [
                    SELECT Product2Id, UnitPrice
                    FROM PricebookEntry
                    WHERE Pricebook2.IsStandard = true
                      AND Product2Id IN :productIds
                      AND IsActive = true
                    WITH USER_MODE
                ];
            }
            for (PricebookEntry pbe : pbes) {
                priceByProductId.put(pbe.Product2Id, pbe.UnitPrice);
            }
        }

        // 5. Calculate estimated costs
        Decimal estLaborHours = 0;
        Decimal estLaborCost = 0;
        Decimal estMaterialsCost = 0;

        if (wo.WorkType != null && wo.WorkType.EstimatedDuration != null) {
            if (wo.WorkType.DurationType == 'Minutes') {
                estLaborHours = wo.WorkType.EstimatedDuration / 60.0;
            } else {
                estLaborHours = wo.WorkType.EstimatedDuration;
            }
        }

        for (ProductRequired pr : prodReqs) {
            Decimal qty = pr.QuantityRequired != null ? pr.QuantityRequired : 0;
            Decimal price = priceByProductId.containsKey(pr.Product2Id)
                ? priceByProductId.get(pr.Product2Id) : 0;
            if (laborProductIds.contains(pr.Product2Id)) {
                estLaborCost += qty * price;
            } else {
                estMaterialsCost += qty * price;
            }
        }

        result.estimatedLaborHours = estLaborHours;
        result.estimatedLaborCost = estLaborCost;
        result.estimatedMaterialsCost = estMaterialsCost;
        result.estimatedTotalCost = estLaborCost + estMaterialsCost;
        result.hasEstimate = !prodReqs.isEmpty();

        // 6. Query ProductConsumed for actuals
        List<ProductConsumed> consumed = [
            SELECT Id, QuantityConsumed, UnitPrice, Product2Id
            FROM ProductConsumed
            WHERE WorkOrderId = :workOrderId
            WITH USER_MODE
        ];

        // Materials actuals from ProductConsumed (exclude labor products)
        Decimal actMaterialsCost = 0;
        for (ProductConsumed pc : consumed) {
            if (!laborProductIds.contains(pc.Product2Id)) {
                Decimal qty = pc.QuantityConsumed != null ? pc.QuantityConsumed : 0;
                Decimal price = pc.UnitPrice != null ? pc.UnitPrice : 0;
                actMaterialsCost += qty * price;
            }
        }

        // 7. Query TimeSheetEntry for actual labor hours via WorkOrderId
        Decimal actualHours = 0;
        List<TimeSheetEntry> entries = [
            SELECT Id, DurationInMinutes, StartTime, EndTime
            FROM TimeSheetEntry
            WHERE WorkOrderId = :workOrderId
            WITH USER_MODE
        ];
        for (TimeSheetEntry tse : entries) {
            if (tse.DurationInMinutes != null) {
                actualHours += tse.DurationInMinutes / 60.0;
            } else if (tse.StartTime != null && tse.EndTime != null) {
                Long ms = tse.EndTime.getTime() - tse.StartTime.getTime();
                actualHours += (Decimal.valueOf(ms) / 3600000);
            }
        }

        // Actual labor cost = timesheet hours * labor rate (timesheet is source of truth)
        Decimal actLaborCost = 0;
        if (actualHours > 0 && !laborProductIds.isEmpty()) {
            Id laborId = new List<Id>(laborProductIds)[0];
            Decimal laborRate = priceByProductId.containsKey(laborId)
                ? priceByProductId.get(laborId) : 0;
            actLaborCost = actualHours * laborRate;
        }

        result.actualLaborHours = actualHours;
        result.actualLaborCost = actLaborCost;
        result.actualMaterialsCost = actMaterialsCost;
        result.actualTotalCost = actLaborCost + actMaterialsCost;
        result.hasActuals = !consumed.isEmpty() || actualHours > 0;

        // 8. Expenses from standard Expense object
        Decimal totalExpenses = 0;
        List<Expense> expenses = [
            SELECT Id, Amount
            FROM Expense
            WHERE WorkOrderId = :workOrderId
            WITH USER_MODE
        ];
        for (Expense exp : expenses) {
            if (exp.Amount != null) {
                totalExpenses += exp.Amount;
            }
        }
        result.totalExpenses = totalExpenses;

        return result;
    }

    public class ProfitabilityData {
        @AuraEnabled public Decimal estimatedLaborHours = 0;
        @AuraEnabled public Decimal actualLaborHours = 0;
        @AuraEnabled public Decimal estimatedLaborCost = 0;
        @AuraEnabled public Decimal actualLaborCost = 0;
        @AuraEnabled public Decimal estimatedMaterialsCost = 0;
        @AuraEnabled public Decimal actualMaterialsCost = 0;
        @AuraEnabled public Decimal estimatedTotalCost = 0;
        @AuraEnabled public Decimal actualTotalCost = 0;
        @AuraEnabled public Boolean hasEstimate = false;
        @AuraEnabled public Boolean hasActuals = false;
        @AuraEnabled public Decimal totalExpenses = 0;
    }
}
