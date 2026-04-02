# SFS Job Costing LWC

A Lightning Web Component for Salesforce Field Service that provides real-time cost tracking directly on the Work Order record page.

![Job Costing LWC](https://img.shields.io/badge/Salesforce-Field%20Service-00A1E0?logo=salesforce) ![API Version](https://img.shields.io/badge/API%20Version-62.0-green)

## What It Does

The Job Costing LWC compares estimated vs. actual spend across labor hours, labor dollars, and materials. Variance percentages and color-coded progress bars make it immediately clear which cost categories are tracking on budget and which are running over. A header badge summarizes overall budget status at a glance.

Expenses like travel, meals, and lodging are displayed in a separate section since they're typically non-billable and shouldn't distort the estimate-to-actual comparison.

**Important:** This is job *costing*, not job *profitability* — it tracks what was planned vs. what was consumed, but does not factor in billing rates, markup, or profit margins on labor or materials. It answers "did we spend what we expected?" rather than "did we make money?" To achieve true profitability analysis, you could integrate with a system of record like an ERP to pull in revenue and margin data, or add custom fields on the Work Order to capture billing rates and markup percentages, allowing the component to calculate actual profit per job.

## Data Sources

| Row | Estimated Source | Actual Source |
|-----|-----------------|---------------|
| Labor (hrs) | `WorkType.EstimatedDuration` | `TimeSheetEntry` (summed by Work Order) |
| Labor ($) | `ProductRequired` (Labor product qty x price) | Timesheet hours x labor rate from `PricebookEntry` |
| Materials | `ProductRequired` (non-Labor products qty x price) | `ProductConsumed` (qty x unit price) |
| Expenses | — | Standard `Expense` object (summed by Work Order) |

- Estimates come from `ProductRequired` records on the Work Order (falls back to `WorkType` if none exist on the WO directly).
- Prices are resolved from the Work Order's `Pricebook2Id` (falls back to the standard pricebook).

## Components

| File | Description |
|------|-------------|
| `RN_SFS_JobCostingController.cls` | Apex controller — queries estimates, actuals, and expenses |
| `RN_SFS_JobCostingControllerTest.cls` | Test class with 90%+ coverage |
| `rnSfsJobCosting/` | LWC — UI rendering, variance calculations, formatting |

## Prerequisites

- Salesforce org with **Field Service** enabled
- Products and Pricebook Entries configured (at least one "Labor" product)
- `ProductRequired` records on Work Types or Work Orders for estimates
- Standard `Expense` object enabled (available in orgs with Field Service)

## Installation

### Deploy to your org

```bash
sf project deploy start --source-dir force-app -o <your-org-alias>
```

### Add to Work Order page

1. Open a Work Order record → **Setup** (gear) → **Edit Page**
2. Drag the **Job Costing** component onto the page layout
3. Save and activate

## Styling

The component uses SLDS-compliant colors from the [Lightning Design System](https://www.lightningdesignsystem.com):

- **Green** (`#2E844A`) — under budget
- **Red** (`#C23934`) — over budget
- **Warning** (`#DD7A01`) — expenses
- **Neutral grays** — borders, backgrounds, secondary text

## License

MIT
