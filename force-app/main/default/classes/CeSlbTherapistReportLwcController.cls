// Use without sharing to match search controller and allow community users to view therapist reports
// The search controller uses without sharing, so contacts found in search should be viewable in reports
public without sharing class CeSlbTherapistReportLwcController {
    
    // Wrapper for Contact data (field names must be valid Apex identifiers)
    public class ContactWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String firstName { get; set; }
        @AuraEnabled public String lastName { get; set; }
        @AuraEnabled public String middleName { get; set; }
        @AuraEnabled public String previouslyKnownAs { get; set; }
        @AuraEnabled public String suffix { get; set; }
        @AuraEnabled public String ssnLast4 { get; set; }
        @AuraEnabled public Date birthdate { get; set; }
        @AuraEnabled public Date dateOfDeath { get; set; }
        @AuraEnabled public Boolean examResultAdjusted { get; set; }
    }
    
    // Wrapper for Contact Information
    public class ContactInformationWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String contactName { get; set; }
        @AuraEnabled public String addressStreet { get; set; }
        @AuraEnabled public String addressCity { get; set; }
        @AuraEnabled public String addressStateCode { get; set; }
        @AuraEnabled public String addressPostalCode { get; set; }
        @AuraEnabled public String addressCountryCode { get; set; }
        @AuraEnabled public String primaryPhone { get; set; }
        @AuraEnabled public String secondaryPhone { get; set; }
        @AuraEnabled public String source { get; set; }
        @AuraEnabled public DateTime systemModstamp { get; set; }
    }
    
    // Wrapper for State Licensing
    public class StateLicensingWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String licenseNumber { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Date issueDate { get; set; }
        @AuraEnabled public Date expirationDate { get; set; }
        @AuraEnabled public String source { get; set; }
    }
    
    // Wrapper for Core Massage School
    public class CoreMassageSchoolWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String state { get; set; }
        @AuraEnabled public String city { get; set; }
        @AuraEnabled public String otherSchoolLocation { get; set; }
        @AuraEnabled public Date completionGraduationDate { get; set; }
        @AuraEnabled public String source { get; set; }
        @AuraEnabled public DateTime systemModstamp { get; set; }
    }
    
    // Wrapper for Board Disciplinary Action
    public class BoardDisciplinaryActionWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String source { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Date dateOfLastAction { get; set; }
        @AuraEnabled public String npdbCode { get; set; }
        @AuraEnabled public String details { get; set; }
    }
    
    // Wrapper for PCE
    public class PCEWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String contactId { get; set; }
        @AuraEnabled public Date completedOn { get; set; }
        @AuraEnabled public String courseName { get; set; }
        @AuraEnabled public Decimal hoursEarned { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public String subCategory { get; set; }
        @AuraEnabled public String courseType { get; set; }
        @AuraEnabled public String imageUrl { get; set; }
        @AuraEnabled public String url { get; set; }
    }
    
    // Main wrapper for all report data
    public class TherapistReportData {
        @AuraEnabled public ContactWrapper contact { get; set; }
        @AuraEnabled public List<ContactInformationWrapper> contactInformations { get; set; }
        @AuraEnabled public List<StateLicensingWrapper> licenses { get; set; }
        @AuraEnabled public List<CoreMassageSchoolWrapper> schools { get; set; }
        @AuraEnabled public List<BoardDisciplinaryActionWrapper> disciplinaryActions { get; set; }
        @AuraEnabled public List<PCEWrapper> pceWrappers { get; set; }
        @AuraEnabled public Boolean hasUserManagementAccess { get; set; }
    }
    
    @AuraEnabled(cacheable=false)
    public static TherapistReportData getTherapistReportData(String therapistId) {
        TherapistReportData reportData = new TherapistReportData();
        
        if (String.isBlank(therapistId)) {
            throw new AuraHandledException('Therapist ID is required');
        }
        
        try {
            // Validate therapistId format
            if (therapistId.length() != 15 && therapistId.length() != 18) {
                throw new AuraHandledException('Invalid therapist ID format: ' + therapistId);
            }
            
            // First try a simple query to check if contact exists and is accessible
            List<Contact> basicCheck = [
                SELECT Id, RecordTypeId 
                FROM Contact 
                WHERE Id = :therapistId 
                LIMIT 1
            ];
            
            if (basicCheck.isEmpty()) {
                // Contact doesn't exist or user doesn't have access
                System.debug('Contact not accessible for ID: ' + therapistId);
                System.debug('User: ' + UserInfo.getUserId() + ', Profile: ' + UserInfo.getProfileId());
                throw new AuraHandledException('Therapist not found. The contact may have been deleted or you may not have access to view it. Contact ID: ' + therapistId);
            }
            
            // Now get full contact details
            List<Contact> contacts = [
                SELECT Id, Name, FirstName, LastName, Middle_Name__c, Previously_Known_As__c, 
                       Suffix__c, SSN_Last_4_Digits__c, Date_Of_Death__c, GenderIdentity, 
                       Birthdate, Exam_Result_Adjusted__c, RecordTypeId, RecordType.DeveloperName
                FROM Contact 
                WHERE Id = :therapistId 
                LIMIT 1
            ];
            
            if (contacts.isEmpty()) {
                // This shouldn't happen if basicCheck passed, but handle it anyway
                throw new AuraHandledException('Therapist not found. You may not have access to view all required fields for this contact.');
            }
            
            Contact contact = contacts[0];
            
            // Log RecordType for debugging (don't block if wrong RecordType)
            if (contact.RecordTypeId != null && contact.RecordType.DeveloperName != null) {
                System.debug('Contact RecordType: ' + contact.RecordType.DeveloperName + ' for ID: ' + therapistId);
            }
            
            reportData.contact = new ContactWrapper();
            reportData.contact.id = contact.Id;
            reportData.contact.name = contact.Name;
            reportData.contact.firstName = contact.FirstName;
            reportData.contact.lastName = contact.LastName;
            reportData.contact.middleName = contact.Middle_Name__c;
            reportData.contact.previouslyKnownAs = contact.Previously_Known_As__c;
            reportData.contact.suffix = contact.Suffix__c;
            reportData.contact.ssnLast4 = contact.SSN_Last_4_Digits__c;
            reportData.contact.birthdate = contact.Birthdate;
            reportData.contact.dateOfDeath = contact.Date_Of_Death__c;
            reportData.contact.examResultAdjusted = contact.Exam_Result_Adjusted__c != null ? contact.Exam_Result_Adjusted__c : false;
            
            // Get Contact Informations
            List<Contact_Information__c> contactInfos = [
                SELECT Id, Contact_Name__c, Address__Street__s, Address__City__s, 
                       Address__PostalCode__s, Address__CountryCode__s, Primary_Phone__c, 
                       Secondary_Phone__c, Address__StateCode__s, Source__c, SystemModstamp
                FROM Contact_Information__c 
                WHERE Contact__c = :therapistId 
                ORDER BY SystemModstamp DESC
            ];
            
            reportData.contactInformations = new List<ContactInformationWrapper>();
            for (Contact_Information__c ci : contactInfos) {
                ContactInformationWrapper wrapper = new ContactInformationWrapper();
                wrapper.id = ci.Id;
                wrapper.contactName = ci.Contact_Name__c;
                wrapper.addressStreet = ci.Address__Street__s;
                wrapper.addressCity = ci.Address__City__s;
                wrapper.addressStateCode = ci.Address__StateCode__s;
                wrapper.addressPostalCode = ci.Address__PostalCode__s;
                wrapper.addressCountryCode = ci.Address__CountryCode__s;
                wrapper.primaryPhone = ci.Primary_Phone__c;
                wrapper.secondaryPhone = ci.Secondary_Phone__c;
                wrapper.source = ci.Source__c;
                wrapper.systemModstamp = ci.SystemModstamp;
                reportData.contactInformations.add(wrapper);
            }
            
            // Get State Licenses
            List<State_Licensing__c> licenses = [
                SELECT Id, Number__c, Type__c, Status__c, Issue_Date__c, 
                       Expiration_Date__c, Source__c
                FROM State_Licensing__c 
                WHERE Contact__c = :therapistId 
                ORDER BY Expiration_Date__c DESC NULLS LAST
            ];
            
            reportData.licenses = new List<StateLicensingWrapper>();
            for (State_Licensing__c lic : licenses) {
                StateLicensingWrapper wrapper = new StateLicensingWrapper();
                wrapper.id = lic.Id;
                wrapper.licenseNumber = lic.Number__c;
                wrapper.type = lic.Type__c;
                wrapper.status = lic.Status__c;
                wrapper.issueDate = lic.Issue_Date__c;
                wrapper.expirationDate = lic.Expiration_Date__c;
                wrapper.source = lic.Source__c;
                reportData.licenses.add(wrapper);
            }
            
            // Get Core Massage Schools
            List<Core_Massage_School__c> schools = [
                SELECT Id, Name__c, State__c, City__c, Completion_Graduation_Date__c, 
                       Source__c, SystemModstamp, Other_School_Location__c
                FROM Core_Massage_School__c 
                WHERE Contact__c = :therapistId 
                ORDER BY SystemModstamp DESC
            ];
            
            reportData.schools = new List<CoreMassageSchoolWrapper>();
            for (Core_Massage_School__c school : schools) {
                CoreMassageSchoolWrapper wrapper = new CoreMassageSchoolWrapper();
                wrapper.id = school.Id;
                wrapper.name = school.Name__c;
                wrapper.state = school.State__c;
                wrapper.city = school.City__c;
                wrapper.otherSchoolLocation = school.Other_School_Location__c;
                wrapper.completionGraduationDate = school.Completion_Graduation_Date__c;
                wrapper.source = school.Source__c;
                wrapper.systemModstamp = school.SystemModstamp;
                reportData.schools.add(wrapper);
            }
            
            // Get Board Disciplinary Actions
            List<Board_Disciplinary_Action__c> disciplinaryActions = [
                SELECT Id, Source__c, Status__c, Date_of_Last_Action__c, 
                       NPDB_Code__c, Details__c
                FROM Board_Disciplinary_Action__c 
                WHERE Contact__c = :therapistId 
                ORDER BY Date_of_Last_Action__c DESC NULLS LAST
            ];
            
            reportData.disciplinaryActions = new List<BoardDisciplinaryActionWrapper>();
            for (Board_Disciplinary_Action__c da : disciplinaryActions) {
                BoardDisciplinaryActionWrapper wrapper = new BoardDisciplinaryActionWrapper();
                wrapper.id = da.Id;
                wrapper.source = da.Source__c;
                wrapper.status = da.Status__c;
                wrapper.dateOfLastAction = da.Date_of_Last_Action__c;
                wrapper.npdbCode = da.NPDB_Code__c;
                wrapper.details = da.Details__c;
                reportData.disciplinaryActions.add(wrapper);
            }
            
            // Get Professional Continuing Education
            List<Professional_Continuing_Education__c> pces = [
                SELECT Id, Contact__c, Completed_On__c,
                       Session__r.Course__r.Course_Name__c,
                       Session__r.Hours_Earned__c,
                       Session__r.Course__r.Account__r.Status__c,
                       Session__r.Course__r.Status__c,
                       Session__r.Status__c,
                       Status__c,
                       Session__r.Course__r.Account__r.Id,
                       Session__r.Course__r.Category__c,
                       Session__r.Course__r.Sub_Category__c,
                       Session__r.RecordType.Name
                FROM Professional_Continuing_Education__c
                WHERE Contact__c = :therapistId
                ORDER BY Completed_On__c DESC NULLS LAST
            ];
            
            reportData.pceWrappers = new List<PCEWrapper>();
            for (Professional_Continuing_Education__c pce : pces) {
                PCEWrapper wrapper = new PCEWrapper();
                wrapper.id = pce.Id;
                wrapper.contactId = pce.Contact__c;
                wrapper.completedOn = pce.Completed_On__c;
                
                // Safely access relationship fields (they might be null)
                if (pce.Session__r != null && pce.Session__r.Course__r != null) {
                    wrapper.courseName = pce.Session__r.Course__r.Course_Name__c;
                    wrapper.hoursEarned = pce.Session__r.Hours_Earned__c;
                    wrapper.category = pce.Session__r.Course__r.Category__c;
                    wrapper.subCategory = pce.Session__r.Course__r.Sub_Category__c;
                    
                    // Set image URL based on status
                    Set<String> actionsTaken = new Set<String>();
                    if (pce.Session__r.Course__r.Account__r != null && pce.Session__r.Course__r.Account__r.Status__c != null) {
                        actionsTaken.add(pce.Session__r.Course__r.Account__r.Status__c);
                    }
                    if (pce.Session__r.Course__r.Status__c != null) {
                        actionsTaken.add(pce.Session__r.Course__r.Status__c);
                    }
                    if (pce.Session__r.Status__c != null) {
                        actionsTaken.add(pce.Session__r.Status__c);
                    }
                    if (pce.Status__c != null) {
                        actionsTaken.add(pce.Status__c);
                    }
                    
                    if (actionsTaken.contains('Revoked')) {
                        wrapper.imageUrl = 'CE_Action_Icons/revoked-warning.png';
                    } else if (actionsTaken.contains('Provisional & Restricted')) {
                        wrapper.imageUrl = 'CE_Action_Icons/provisional-restricted.png';
                    } else if (actionsTaken.contains('Restricted')) {
                        wrapper.imageUrl = 'CE_Action_Icons/restricted-warning.png';
                    } else if (actionsTaken.contains('Provisional & Under Review')) {
                        wrapper.imageUrl = 'CE_Action_Icons/provisional-under-review-eye.png';
                    } else if (actionsTaken.contains('Under Review')) {
                        wrapper.imageUrl = 'CE_Action_Icons/under-review-eye.png';
                    } else if (actionsTaken.contains('Provisional')) {
                        wrapper.imageUrl = 'CE_Action_Icons/provisional-flag.png';
                    } else if (actionsTaken.contains('Provisional & Internal Investigation')) {
                        wrapper.imageUrl = 'CE_Action_Icons/provisional-flag.png';
                    }
                }
                
                if (pce.Session__r != null && pce.Session__r.RecordType != null) {
                    wrapper.courseType = pce.Session__r.RecordType.Name;
                }
                
                // Build URL for PCE report
                String communityUrl = Site.getBaseUrl();
                wrapper.url = communityUrl + '/s/slb-pce-report?recordId=' + pce.Id + '&id=' + pce.Contact__c;
                
                reportData.pceWrappers.add(wrapper);
            }
            
            // Get hasUserManagementAccess (similar to other controllers)
            reportData.hasUserManagementAccess = false; // Default, update based on requirements
            
        } catch (AuraHandledException e) {
            // Re-throw AuraHandledException as-is
            throw e;
        } catch (QueryException e) {
            System.debug('Query Exception in getTherapistReportData: ' + e.getMessage() + ' Stack: ' + e.getStackTraceString());
            throw new AuraHandledException('Error loading therapist report data: Query failed. ' + e.getMessage());
        } catch (DmlException e) {
            System.debug('DML Exception in getTherapistReportData: ' + e.getMessage() + ' Stack: ' + e.getStackTraceString());
            throw new AuraHandledException('Error loading therapist report data: Database operation failed. ' + e.getMessage());
        } catch (Exception e) {
            System.debug('Error in getTherapistReportData: ' + e.getMessage() + ' Type: ' + e.getTypeName() + ' Stack: ' + e.getStackTraceString());
            throw new AuraHandledException('Error loading therapist report data: ' + e.getMessage() + ' (Type: ' + e.getTypeName() + ')');
        }
        
        return reportData;
    }
}
