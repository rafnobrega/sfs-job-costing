@IsTest
private class RN_SFS_JobCostingControllerTest {

    @TestSetup
    static void setup() {
        // Pricebook
        Id stdPbId = Test.getStandardPricebookId();

        // Products
        Product2 laborProduct = new Product2(Name = 'Labor', Family = 'Labor', IsActive = true);
        Product2 materialProduct = new Product2(Name = 'Air Filter', Family = 'Parts', IsActive = true);
        insert new List<Product2>{ laborProduct, materialProduct };

        PricebookEntry laborPbe = new PricebookEntry(
            Pricebook2Id = stdPbId, Product2Id = laborProduct.Id,
            UnitPrice = 150.00, IsActive = true
        );
        PricebookEntry materialPbe = new PricebookEntry(
            Pricebook2Id = stdPbId, Product2Id = materialProduct.Id,
            UnitPrice = 45.00, IsActive = true
        );
        insert new List<PricebookEntry>{ laborPbe, materialPbe };

        // Work Type
        WorkType wt = new WorkType(
            Name = 'Preventive Maintenance',
            EstimatedDuration = 16,
            DurationType = 'Hours'
        );
        insert wt;

        // Products Required on Work Type
        ProductRequired prLabor = new ProductRequired(
            ParentRecordId = wt.Id, Product2Id = laborProduct.Id,
            QuantityRequired = 16
        );
        ProductRequired prMaterial = new ProductRequired(
            ParentRecordId = wt.Id, Product2Id = materialProduct.Id,
            QuantityRequired = 4
        );
        insert new List<ProductRequired>{ prLabor, prMaterial };

        // Operating Hours (required for ServiceTerritory)
        OperatingHours oh = new OperatingHours(Name = 'Test Hours');
        insert oh;

        // Service Territory
        ServiceTerritory st = new ServiceTerritory(
            Name = 'Test Territory', IsActive = true, OperatingHoursId = oh.Id
        );
        insert st;

        // Work Order with actuals
        WorkOrder woWithActuals = new WorkOrder(
            Subject = 'Test WO With Actuals',
            WorkTypeId = wt.Id,
            Pricebook2Id = stdPbId,
            ServiceTerritoryId = st.Id
        );
        insert woWithActuals;

        // Work Order without estimates (no WorkType)
        WorkOrder woNoEstimate = new WorkOrder(
            Subject = 'Test WO No Estimate',
            ServiceTerritoryId = st.Id
        );
        insert woNoEstimate;

        // ProductConsumed requires a ProductItem which requires a Location
        Schema.Location loc = new Schema.Location(
            Name = 'Warehouse', LocationType = 'Warehouse'
        );
        insert loc;

        ProductItem piMaterial = new ProductItem(
            Product2Id = materialProduct.Id,
            LocationId = loc.Id,
            QuantityOnHand = 100
        );
        insert piMaterial;

        ProductConsumed pc = new ProductConsumed(
            WorkOrderId = woWithActuals.Id,
            ProductItemId = piMaterial.Id,
            QuantityConsumed = 3
        );
        insert pc;

        // TimeSheet + TimeSheetEntry for labor actuals
        ServiceResource sr = new ServiceResource(
            RelatedRecordId = UserInfo.getUserId(),
            Name = 'Test Tech',
            IsActive = true
        );
        insert sr;

        TimeSheet ts = new TimeSheet(
            ServiceResourceId = sr.Id,
            StartDate = Date.today().addDays(-1),
            EndDate = Date.today()
        );
        insert ts;

        TimeSheetEntry tse = new TimeSheetEntry(
            TimeSheetId = ts.Id,
            WorkOrderId = woWithActuals.Id,
            StartTime = DateTime.now().addHours(-8),
            EndTime = DateTime.now(),
            Type = 'Normal'
        );
        insert tse;

        // Expense record
        Expense exp = new Expense(
            WorkOrderId = woWithActuals.Id,
            Amount = 425.50,
            TransactionDate = Date.today(),
            Title = 'Flight EWR to LAX'
        );
        insert exp;
    }

    @IsTest
    static void testWithEstimatesAndActuals() {
        WorkOrder wo = [SELECT Id FROM WorkOrder WHERE Subject = 'Test WO With Actuals' LIMIT 1];

        Test.startTest();
        RN_SFS_JobCostingController.ProfitabilityData result =
            RN_SFS_JobCostingController.getProfitability(wo.Id);
        Test.stopTest();

        // Estimates: 16 labor hrs * $150 = $2400, 4 materials * $45 = $180
        System.assertEquals(16, result.estimatedLaborHours, 'Expected 16 estimated labor hours');
        System.assertEquals(2400.00, result.estimatedLaborCost, 'Expected $2400 estimated labor cost');
        System.assertEquals(180.00, result.estimatedMaterialsCost, 'Expected $180 estimated materials cost');
        System.assertEquals(2580.00, result.estimatedTotalCost, 'Expected $2580 estimated total cost');
        System.assert(result.hasEstimate, 'Should have estimate data');

        // Actuals
        System.assert(result.actualLaborHours > 0, 'Should have actual labor hours from timesheet');
        System.assert(result.hasActuals, 'Should have actuals data');

        // Expenses
        System.assertEquals(425.50, result.totalExpenses, 'Expected $425.50 in expenses');
    }

    @IsTest
    static void testNoEstimate() {
        WorkOrder wo = [SELECT Id FROM WorkOrder WHERE Subject = 'Test WO No Estimate' LIMIT 1];

        Test.startTest();
        RN_SFS_JobCostingController.ProfitabilityData result =
            RN_SFS_JobCostingController.getProfitability(wo.Id);
        Test.stopTest();

        System.assert(!result.hasEstimate, 'Should not have estimate data');
        System.assertEquals(0, result.estimatedLaborCost, 'No estimated labor cost');
        System.assertEquals(0, result.estimatedMaterialsCost, 'No estimated materials cost');
        System.assertEquals(0, result.totalExpenses, 'No expenses');
    }

    @IsTest
    static void testProfitabilityDataDefaults() {
        RN_SFS_JobCostingController.ProfitabilityData data =
            new RN_SFS_JobCostingController.ProfitabilityData();

        System.assertEquals(0, data.estimatedLaborHours);
        System.assertEquals(0, data.actualLaborHours);
        System.assertEquals(0, data.estimatedLaborCost);
        System.assertEquals(0, data.actualLaborCost);
        System.assertEquals(0, data.estimatedMaterialsCost);
        System.assertEquals(0, data.actualMaterialsCost);
        System.assertEquals(0, data.estimatedTotalCost);
        System.assertEquals(0, data.actualTotalCost);
        System.assertEquals(0, data.totalExpenses);
        System.assert(!data.hasEstimate);
        System.assert(!data.hasActuals);
    }
}
