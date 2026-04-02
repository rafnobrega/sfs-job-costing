import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getProfitability from '@salesforce/apex/RN_SFS_JobCostingController.getProfitability';

export default class RnSfsJobCosting extends LightningElement {
    @api recordId;

    profitData;
    error;
    wiredResult;
    isRefreshing = false;

    @wire(getProfitability, { workOrderId: '$recordId' })
    wiredProfitability(result) {
        this.wiredResult = result;
        if (result.data) {
            this.profitData = result.data;
            this.error = undefined;
            this.isRefreshing = false;
        } else if (result.error) {
            this.error = result.error;
            this.profitData = undefined;
            this.isRefreshing = false;
        }
    }

    handleRefresh() {
        this.isRefreshing = true;
        refreshApex(this.wiredResult);
    }

    get hasData() {
        return this.profitData != null;
    }

    get hasEstimate() {
        return this.profitData?.hasEstimate === true;
    }

    get hasActuals() {
        return this.profitData?.hasActuals === true;
    }

    get isLoading() {
        return !this.profitData && !this.error;
    }

    get showData() {
        return this.hasData && this.hasEstimate;
    }

    get showNoEstimate() {
        return this.hasData && !this.hasEstimate;
    }

    get rows() {
        if (!this.profitData) return [];
        const d = this.profitData;
        return [
            this._buildRow('Labor (hrs)', d.estimatedLaborHours, d.actualLaborHours, 'hrs'),
            this._buildRow('Labor ($)', d.estimatedLaborCost, d.actualLaborCost, '$'),
            this._buildRow('Materials', d.estimatedMaterialsCost, d.actualMaterialsCost, '$'),
            this._buildRow('Total', d.estimatedTotalCost, d.actualTotalCost, '$')
        ];
    }

    get hasExpenses() {
        return this.profitData && (Number(this.profitData.totalExpenses) || 0) > 0;
    }

    get expensesDisplay() {
        if (!this.profitData) return '$0.00';
        const total = Number(this.profitData.totalExpenses) || 0;
        return '$' + total.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    get budgetBadgeDisplay() {
        if (!this.profitData) return '';
        const est = Number(this.profitData.estimatedTotalCost) || 0;
        const act = Number(this.profitData.actualTotalCost) || 0;
        if (est === 0) return 'N/A';
        const variance = ((act - est) / est) * 100;
        if (Math.abs(variance) < 0.1) return 'On Budget';
        const sign = variance > 0 ? '+' : '';
        return sign + variance.toFixed(1) + '%';
    }

    get marginIsPositive() {
        if (!this.profitData) return true;
        return (Number(this.profitData.actualTotalCost) || 0) <= (Number(this.profitData.estimatedTotalCost) || 0);
    }

    get marginBadgeClass() {
        return this.marginIsPositive ? 'margin-badge margin-badge-positive' : 'margin-badge margin-badge-negative';
    }

    _buildRow(label, estimated, actual, unit) {
        const est = Number(estimated) || 0;
        const act = Number(actual) || 0;
        const variance = est !== 0 ? ((act - est) / est) * 100 : (act > 0 ? 100 : 0);
        const isOver = act > est;
        const utilization = est !== 0 ? Math.min((act / est) * 100, 100) : 0;

        return {
            label,
            estimated: this._format(est, unit),
            actual: this._format(act, unit),
            varianceDisplay: (variance >= 0 ? '+' : '') + variance.toFixed(1) + '%',
            varianceClass: 'col-variance ' + (isOver ? 'variance-over' : 'variance-under'),
            barStyle: `width: ${utilization}%`,
            barClass: 'bar-fill ' + (isOver ? 'bar-red' : 'bar-green'),
            hasEstimate: est > 0
        };
    }

    _format(value, unit) {
        if (unit === '$') {
            return '$' + value.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
        }
        return value.toFixed(1);
    }
}
