/**
 * Calculates GS Quality for Overall Status and for Customer Satisfaction in PRO Snapshots.
 */
public without sharing class GSOverallCalculationBatch implements Database.Batchable<Project_Report_Out__c>, Database.Stateful {

    private List<Business_Unit__c> businessUnits;
    private Business_Unit__c currentUnit;

    private Double gsOverall;
    private Double gsSatisfaction;
    private Double gsBudget;
    private Double gsTotalOverall;
    private Double gsTotalSatisfaction;
    private Double gsTotalBudget;
    private List<Project_Report_Out__c> proList;
    private Date currentDate;
    private Boolean total;
    private Date cycleStartDate;

    public GSOverallCalculationBatch(List<Business_Unit__c> businessUnits) {
        this.businessUnits = businessUnits;
        if (this.businessUnits.size() > 0) {
            this.currentUnit = this.businessUnits.get(0);
            this.businessUnits.remove(0);
        }
        this.gsOverall = 0;
        this.gsSatisfaction = 0;
        this.gsBudget = 0;
        this.gsTotalOverall = 0;
        this.gsTotalSatisfaction = 0;
        this.gsTotalBudget = 0;
        this.proList = new List<Project_Report_Out__c>();
        this.currentDate = Date.today();
    }

    public GSOverallCalculationBatch(List<Business_Unit__c> businessUnits, Date currentDate, Double gsTotalOverall, Double gsTotalSatisfaction, Double gsTotalBudget) {
        this.businessUnits = businessUnits;
        if (this.businessUnits.size() > 0) {
            this.currentUnit = this.businessUnits.get(0);
            this.businessUnits.remove(0);
        }
        this.gsOverall = 0;
        this.gsSatisfaction = 0;
        this.gsBudget = 0;
        this.gsTotalOverall = gsTotalOverall;
        this.gsTotalSatisfaction = gsTotalSatisfaction;
        this.gsTotalBudget = gsTotalBudget;
        this.proList = new List<Project_Report_Out__c>();
        this.currentDate = currentDate;
    }

    public List<Project_Report_Out__c> start(Database.BatchableContext BC) {
        List<Date> thursDayList = PROHelper.GetAllThursDayOfMonth(this.currentDate.year(), this.currentDate.month());
        List<Date> thursDayListLastMonth = PROHelper.GetAllThursDayOfMonth(this.currentDate.addMonths(-1).year(), this.currentDate.addMonths(-1).month());
        List<Date> thursDayListNextMonth = PROHelper.GetAllThursDayOfMonth(this.currentDate.addMonths(1).year(), this.currentDate.addMonths(1).month());
        Date startDate;
        Date endDate;
        if (this.currentDate < thursDayList[1]) {
            startDate = thursDayListLastMonth[3];
            endDate = thursDayList[1];
        } else if (this.currentDate < thursDayList[3]) {
            startDate = thursDayList[1];
            endDate = thursDayList[3];
        } else {
            startDate = thursDayList[3];
            endDate = thursDayListNextMonth[1];
        }

        this.cycleStartDate = startDate;
        if (this.currentDate == endDate.addDays(-1)) {
            this.total = true; // If last day we calculate total value
        }

        System.debug('Start date : ' + startDate);
        System.debug('End date : ' + endDate);

        if (this.currentUnit == null) {
            return new List<Project_Report_Out__c>();
        }
        return [SELECT Id, Contract__c, Report_Out_Date__c, Contract_Snapshot__c, Contract_Snapshot__r.GS_Quality_Overall_Status__c, Contract_Snapshot__r.GS_Quality_Customer_Satisfaction__c,
                Contract_Snapshot__r.Project_Quality_Overall_Status__c, Contract_Snapshot__r.Customer_Satisfaction_of_services__c, Contract_Snapshot__r.GS_Execution_Budget__c
                FROM Project_Report_Out__c WHERE Contract__r.Prime_Contracting_Business_Unit__c =: this.currentUnit.Id AND Contract_Snapshot__c != ''
                AND Report_Out_Date__c >=: startDate AND Report_Out_Date__c <: endDate];
    }

    public void execute(Database.BatchableContext BC, List<Project_Report_Out__c> scope) {
        try {
            System.debug('Total : ' + this.total);
            System.debug('scope ; ' + scope.size());
            for (Project_Report_Out__c pro : scope) {
                System.debug(pro.Report_Out_Date__c);
                this.gsOverall += pro.Contract_Snapshot__r.Project_Quality_Overall_Status__c != null ? pro.Contract_Snapshot__r.Project_Quality_Overall_Status__c : 0;
                this.gsSatisfaction += pro.Contract_Snapshot__r.Customer_Satisfaction_of_services__c != null ? pro.Contract_Snapshot__r.Customer_Satisfaction_of_services__c : 0;
                this.gsBudget += pro.Contract_Snapshot__r.GS_Execution_Budget__c != null ? pro.Contract_Snapshot__r.GS_Execution_Budget__c : 0;
                this.proList.add(pro);
            }
        } catch (Exception ex) {
            System.debug('Error : ' + ex);
            if (!Test.isRunningTest()) {
                BatchDefaultSettings__c settings = BatchDefaultSettings__c.getOrgDefaults();
                EmailHelper.sendEmailFromException(settings.Error_Emails__c.split(','), 'GS Quality calculation error', 'GS Quality calculation error', ex);
            }
        }
    }

    public void finish(Database.BatchableContext BC) {
        try {
            List<PRO_Contract_Snapshot__c> toUpdate = new List<PRO_Contract_Snapshot__c>();
            System.debug('Total : ' + this.total);
            System.debug('this.gsOverall : ' + this.gsOverall);
            System.debug('this.gsSatisfaction : ' + this.gsSatisfaction);
            System.debug('this.gsBudget : ' + this.gsBudget);
            this.gsTotalOverall += this.gsOverall;
            this.gsTotalSatisfaction += this.gsSatisfaction;
            this.gsTotalBudget += this.gsBudget;

            if (this.gsBudget == 0) {
                this.gsOverall = 0;
                this.gsSatisfaction = 0;
            } else {
                this.gsOverall = 100 * (this.gsOverall / this.gsBudget);
                this.gsSatisfaction = 100 * (this.gsSatisfaction / this.gsBudget);
            }

            List<DContract__c> contractsToUpdate = new List<DContract__c>();
            for (Project_Report_Out__c pro : this.proList) {
                toUpdate.add(new PRO_Contract_Snapshot__c(Id = pro.Contract_Snapshot__c, GS_Quality_Overall_Status__c = this.gsOverall,
                                                      GS_Quality_Customer_Satisfaction__c = this.gsSatisfaction));
                contractsToUpdate.add(new DContract__c(Id = pro.Contract__c, GS_Quality_Overall_Status__c = this.gsOverall,
                                                    GS_Quality_Customer_Satisfaction__c = this.gsSatisfaction));
            }

            if (contractsToUpdate.size() > 0) {
                List<Database.SaveResult> updateResults = Database.update(contractsToUpdate, false);
                String emailBody = '';
                for(Integer i = 0; i < updateResults.size(); i++){
                    if (!updateResults.get(i).isSuccess()){
                        Database.Error error = updateResults.get(i).getErrors().get(0);
                        System.debug('Error : Fields - ' + error.getFields() + ' Message - ' + error.getMessage());
                        emailBody += '<tr><td>' + toUpdate.get(i).Id + '</td><td>' + error.getFields()+ '</td><td>' + error.getStatusCode()+ '</td><td>' + error.getMessage() + '</td></tr>';
                    }
                }

                if (emailBody != '') {
                    BatchDefaultSettings__c settings = BatchDefaultSettings__c.getOrgDefaults();
                    emailBody = '<table border="1"><tr><td>Id</td><td>Fields</td><td>Code</td><td>Error Message</td></tr>' + emailBody + '</table></br>';
                    EmailHelper.sendEmail(settings.Error_Emails__c.split(','), 'GS Quality calculation error', emailBody);
                }
            }

            if (toUpdate.size() > 0) {
                update toUpdate;
            }
        } catch (Exception ex) {
            System.debug('Error : ' + ex);
            if (!Test.isRunningTest()) {
                BatchDefaultSettings__c settings = BatchDefaultSettings__c.getOrgDefaults();
                EmailHelper.sendEmailFromException(settings.Error_Emails__c.split(','), 'GS Quality calculation error', 'GS Quality calculation error', ex);
            }
        }

        if (this.businessUnits.size() > 0) {
            GSOverallCalculationBatch overallBatch = new GSOverallCalculationBatch(this.businessUnits, this.currentDate, this.gsTotalOverall,
                                                                                    this.gsTotalSatisfaction, this.gsTotalBudget);
            Database.executeBatch(overallBatch);
        } else {
            if (this.total == true) {
                System.debug('this.gsTotalOverall ' + this.gsTotalOverall);
                System.debug('this.gsTotalSatisfaction ' + this.gsTotalSatisfaction);
                System.debug('this.gsTotalBudget ' + this.gsTotalBudget);
                if (this.gsTotalBudget != 0) {
                    this.gsTotalOverall = 100 * (this.gsTotalOverall / this.gsTotalBudget);
                    this.gsTotalSatisfaction = 100 * (this.gsTotalSatisfaction / this.gsTotalBudget);
                } else {
                    this.gsTotalOverall = 0;
                    this.gsTotalSatisfaction = 0;
                }
                Contract_Statistic__c cs = new Contract_Statistic__c(PRO_Cycle_Date__c = this.cycleStartDate, GS_Quality_Total_Overall_Status__c = this.gsTotalOverall,
                                                                     GS_Quality_Total_Customer_Satisfaction__c = this.gsTotalSatisfaction);
                insert cs;
            }
            // TODO : Database.executeBatch(new ForPeriodCalcSnapshotBatch(false), 50);
        }
    }

    public void setTotal(Boolean total) {
        this.total = total;
    }
}