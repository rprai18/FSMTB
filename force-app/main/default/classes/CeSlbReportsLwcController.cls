public without sharing class CeSlbReportsLwcController {

    // Row for "Therapists with 3 or More Licenses" (flat list, grouped by therapist in LWC)
    public class ThreeLicenseRow {
        @AuraEnabled public Id therapistId { get; set; }
        @AuraEnabled public String therapistName { get; set; }
        @AuraEnabled public String source { get; set; }
        @AuraEnabled public String licenseNumber { get; set; }
        @AuraEnabled public String licenseType { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Date issueDate { get; set; }
        @AuraEnabled public Date expirationDate { get; set; }
        @AuraEnabled public String therapistNameOnLicense { get; set; }
    }

    // License row for Board Actions and reuse
    public class LicenseRow {
        @AuraEnabled public String source { get; set; }
        @AuraEnabled public String licenseNumber { get; set; }
        @AuraEnabled public String licenseType { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Date issueDate { get; set; }
        @AuraEnabled public Date expirationDate { get; set; }
    }

    // Board/Disciplinary action row
    public class BoardActionRow {
        @AuraEnabled public String source { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Date dateOfLastAction { get; set; }
    }

    // One therapist with licenses + disciplinary actions (Board Actions report)
    public class DisciplineTherapistGroup {
        @AuraEnabled public Id therapistId { get; set; }
        @AuraEnabled public String therapistName { get; set; }
        @AuraEnabled public List<LicenseRow> licenses { get; set; }
        @AuraEnabled public List<BoardActionRow> disciplinaryActions { get; set; }
    }

    // License row for Exam Alerts (includes Name Provided)
    public class ExamAlertLicenseRow {
        @AuraEnabled public String source { get; set; }
        @AuraEnabled public String licenseNumber { get; set; }
        @AuraEnabled public String licenseType { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String nameProvided { get; set; }
    }

    // One therapist with licenses (Exam Alerts report)
    public class ExamAlertTherapistGroup {
        @AuraEnabled public Id therapistId { get; set; }
        @AuraEnabled public String therapistName { get; set; }
        @AuraEnabled public List<ExamAlertLicenseRow> licenses { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<ThreeLicenseRow> getThreeLicenseReport() {
        List<ThreeLicenseRow> rows = new List<ThreeLicenseRow>();

        List<State_Licensing__c> licenses = [
            SELECT Source__c,
                   Number__c,
                   Type__c,
                   Status__c,
                   Issue_Date__c,
                   Expiration_Date__c,
                   Therapist_Name__c,
                   Contact__r.Id,
                   Contact__r.Name,
                   Contact__r.LastName,
                   Contact__r.FirstName
            FROM State_Licensing__c
            WHERE Contact__r.Number_of_License_Records__c > 2
            ORDER BY Contact__r.LastName ASC NULLS LAST, Contact__r.FirstName ASC NULLS LAST, Expiration_Date__c
        ];

        for (State_Licensing__c lic : licenses) {
            if (lic.Contact__r == null) continue;
            ThreeLicenseRow row = new ThreeLicenseRow();
            row.therapistId = lic.Contact__r.Id;
            row.therapistName = lic.Contact__r.Name;
            row.source = lic.Source__c;
            row.licenseNumber = lic.Number__c;
            row.licenseType = lic.Type__c;
            row.status = lic.Status__c;
            row.issueDate = lic.Issue_Date__c;
            row.expirationDate = lic.Expiration_Date__c;
            row.therapistNameOnLicense = lic.Therapist_Name__c;
            rows.add(row);
        }

        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<DisciplineTherapistGroup> getDisciplineReport() {
        List<DisciplineTherapistGroup> groups = new List<DisciplineTherapistGroup>();

        List<Contact> contacts = [
            SELECT Id,
                   Name,
                   (SELECT Source__c,
                           Number__c,
                           Status__c,
                           Type__c,
                           Issue_Date__c,
                           Expiration_Date__c
                    FROM StatesLicensing__r
                    ORDER BY Expiration_Date__c),
                   (SELECT Source__c,
                           Status__c,
                           Date_of_Last_Action__c
                    FROM DisciplinaryActions__r
                    ORDER BY Date_of_Last_Action__c)
            FROM Contact
            WHERE Number_of_License_Records__c > 0
                  AND Number_of_Disciplinary_Actions__c > 0
                  AND Id IN (SELECT Contact__c FROM State_Licensing__c)
            ORDER BY LastName ASC, FirstName DESC
        ];

        for (Contact c : contacts) {
            DisciplineTherapistGroup grp = new DisciplineTherapistGroup();
            grp.therapistId = c.Id;
            grp.therapistName = c.Name;
            grp.licenses = new List<LicenseRow>();
            grp.disciplinaryActions = new List<BoardActionRow>();

            for (State_Licensing__c lic : c.StatesLicensing__r) {
                LicenseRow lr = new LicenseRow();
                lr.source = lic.Source__c;
                lr.licenseNumber = lic.Number__c;
                lr.licenseType = lic.Type__c;
                lr.status = lic.Status__c;
                lr.issueDate = lic.Issue_Date__c;
                lr.expirationDate = lic.Expiration_Date__c;
                grp.licenses.add(lr);
            }

            for (Board_Disciplinary_Action__c da : c.DisciplinaryActions__r) {
                BoardActionRow bar = new BoardActionRow();
                bar.source = da.Source__c;
                bar.status = da.Status__c;
                bar.dateOfLastAction = da.Date_of_Last_Action__c;
                grp.disciplinaryActions.add(bar);
            }

            groups.add(grp);
        }

        return groups;
    }

    @AuraEnabled(cacheable=true)
    public static List<ExamAlertTherapistGroup> getAdjustmentsReport() {
        List<ExamAlertTherapistGroup> groups = new List<ExamAlertTherapistGroup>();

        List<Contact> contacts = [
            SELECT Id,
                   Name,
                   (SELECT Source__c,
                           Number__c,
                           Status__c,
                           Type__c,
                           Therapist_Name__c
                    FROM StatesLicensing__r)
            FROM Contact
            WHERE Exam_Result_Adjusted__c = true
            ORDER BY LastName ASC
        ];

        for (Contact c : contacts) {
            ExamAlertTherapistGroup grp = new ExamAlertTherapistGroup();
            grp.therapistId = c.Id;
            grp.therapistName = c.Name;
            grp.licenses = new List<ExamAlertLicenseRow>();

            for (State_Licensing__c lic : c.StatesLicensing__r) {
                ExamAlertLicenseRow lr = new ExamAlertLicenseRow();
                lr.source = lic.Source__c;
                lr.licenseNumber = lic.Number__c;
                lr.licenseType = lic.Type__c;
                lr.status = lic.Status__c;
                lr.nameProvided = lic.Therapist_Name__c;
                grp.licenses.add(lr);
            }

            groups.add(grp);
        }

        return groups;
    }
}

