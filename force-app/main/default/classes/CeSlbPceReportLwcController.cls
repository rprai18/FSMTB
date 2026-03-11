public without sharing class CeSlbPceReportLwcController {

    public class PceReportData {
        @AuraEnabled public String therapistName { get; set; }
        @AuraEnabled public List<LicenseRow> stateLicenses { get; set; }
        @AuraEnabled public List<AdjustmentRow> adjustments { get; set; }
        @AuraEnabled public CourseInfo courseInfo { get; set; }
        @AuraEnabled public SessionInfo sessionInfo { get; set; }
    }

    public class LicenseRow {
        @AuraEnabled public String source { get; set; }
        @AuraEnabled public String licenseNumber { get; set; }
        @AuraEnabled public String licenseType { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Date issueDate { get; set; }
        @AuraEnabled public Date expirationDate { get; set; }
    }

    public class AdjustmentRow {
        @AuraEnabled public String action { get; set; }
        @AuraEnabled public Date startDate { get; set; }
        @AuraEnabled public Date endDate { get; set; }
        @AuraEnabled public String reason { get; set; }
    }

    public class CourseInfo {
        @AuraEnabled public String courseName { get; set; }
        @AuraEnabled public String courseProvider { get; set; }
        @AuraEnabled public String courseCategory { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String courseId { get; set; }
        @AuraEnabled public String registrationPhone { get; set; }
        @AuraEnabled public String registrationWebsite { get; set; }
    }

    public class SessionInfo {
        @AuraEnabled public String sessionType { get; set; }
        @AuraEnabled public Decimal hoursEarned { get; set; }
        @AuraEnabled public Decimal handsOnPercent { get; set; }
        @AuraEnabled public Decimal lecturePercent { get; set; }
        @AuraEnabled public Date completedOn { get; set; }
        @AuraEnabled public String sessionId { get; set; }
        @AuraEnabled public String instructor { get; set; }
        @AuraEnabled public String city { get; set; }
        @AuraEnabled public String state { get; set; }
    }

    @AuraEnabled(cacheable=false)
    public static PceReportData getPceReportData(String recordId, String contactId) {
        if (String.isBlank(recordId) || String.isBlank(contactId)) {
            throw new AuraHandledException('Record ID and Contact ID are required.');
        }

        PceReportData data = new PceReportData();
        data.stateLicenses = new List<LicenseRow>();
        data.adjustments = new List<AdjustmentRow>();

        // Therapist name
        List<Contact> contacts = [
            SELECT Id, Name
            FROM Contact
            WHERE Id = :contactId
            LIMIT 1
        ];
        if (contacts.isEmpty()) {
            throw new AuraHandledException('Therapist not found.');
        }
        data.therapistName = contacts[0].Name;

        // State Licensing for this therapist
        List<State_Licensing__c> licenses = [
            SELECT Source__c, Number__c, Type__c, Status__c, Issue_Date__c, Expiration_Date__c
            FROM State_Licensing__c
            WHERE Contact__c = :contactId
            ORDER BY Expiration_Date__c DESC NULLS LAST
        ];
        for (State_Licensing__c lic : licenses) {
            LicenseRow row = new LicenseRow();
            row.source = lic.Source__c;
            row.licenseNumber = lic.Number__c;
            row.licenseType = lic.Type__c;
            row.status = lic.Status__c;
            row.issueDate = lic.Issue_Date__c;
            row.expirationDate = lic.Expiration_Date__c;
            data.stateLicenses.add(row);
        }

        // PCE record with Session and Course
        List<Professional_Continuing_Education__c> pces = [
            SELECT Id, Contact__c, Completed_On__c,
                   Session__r.Id, Session__r.Name, Session__r.RecordType.Name,
                   Session__r.Hours_Earned__c, Session__r.Instructor_Name__c, Session__r.Session_Type__c,
                   Session__r.Course__r.Id, Session__r.Course__r.Name, Session__r.Course__r.Course_Name__c,
                   Session__r.Course__r.Description__c, Session__r.Course__r.Category__c,
                   Session__r.Course__r.Sub_Category__c, Session__r.Course__r.Registration_Phone__c,
                   Session__r.Course__r.Registration_Website__c, Session__r.Course__r.Account__r.Name
            FROM Professional_Continuing_Education__c
            WHERE Id = :recordId AND Contact__c = :contactId
            LIMIT 1
        ];

        if (pces.isEmpty()) {
            throw new AuraHandledException('PCE record not found or you do not have access to view it.');
        }

        Professional_Continuing_Education__c pce = pces[0];

        // Course Information
        data.courseInfo = new CourseInfo();
        if (pce.Session__r != null && pce.Session__r.Course__r != null) {
            data.courseInfo.courseName = pce.Session__r.Course__r.Course_Name__c;
            data.courseInfo.courseProvider = pce.Session__r.Course__r.Account__r != null ? pce.Session__r.Course__r.Account__r.Name : null;
            data.courseInfo.courseCategory = pce.Session__r.Course__r.Category__c;
            if (String.isNotBlank(pce.Session__r.Course__r.Sub_Category__c)) {
                data.courseInfo.courseCategory = (data.courseInfo.courseCategory != null ? data.courseInfo.courseCategory + ' - ' : '') + pce.Session__r.Course__r.Sub_Category__c;
            }
            data.courseInfo.description = pce.Session__r.Course__r.Description__c;
            data.courseInfo.courseId = pce.Session__r.Course__r.Name;
            data.courseInfo.registrationPhone = pce.Session__r.Course__r.Registration_Phone__c;
            data.courseInfo.registrationWebsite = pce.Session__r.Course__r.Registration_Website__c;
        }

        // Session Information
        data.sessionInfo = new SessionInfo();
        data.sessionInfo.completedOn = pce.Completed_On__c;
        if (pce.Session__r != null) {
            data.sessionInfo.sessionType = pce.Session__r.RecordType != null ? pce.Session__r.RecordType.Name : pce.Session__r.Session_Type__c;
            data.sessionInfo.hoursEarned = pce.Session__r.Hours_Earned__c;
            data.sessionInfo.sessionId = pce.Session__r.Name;
            data.sessionInfo.instructor = pce.Session__r.Instructor_Name__c;
        }

        // CE Actions (Adjustment)
        List<CE_Action__c> actions = [
            SELECT Action__c, Start_Date__c, End_Date__c, Reason__c
            FROM CE_Action__c
            WHERE Professional_Continuing_Education__c = :recordId
            ORDER BY Start_Date__c DESC NULLS LAST
        ];
        for (CE_Action__c act : actions) {
            AdjustmentRow ar = new AdjustmentRow();
            ar.action = act.Action__c;
            ar.startDate = act.Start_Date__c;
            ar.endDate = act.End_Date__c;
            ar.reason = act.Reason__c;
            data.adjustments.add(ar);
        }

        return data;
    }
}
