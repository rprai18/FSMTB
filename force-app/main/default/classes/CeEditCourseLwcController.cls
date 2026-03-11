public with sharing class CeEditCourseLwcController {
    
    private static final String COMPLETE = 'Complete';
    private static final String DENIED = 'Denied';
    private static final String DRAFT = 'Draft';
    private static final String INACTIVE = 'Inactive';
    private static final String PENDING = 'Pending';
    private static final String PUBLISHED = 'Published';
    private static final String UNDER_REVIEW = 'Under Review';
    private static final String REVOKED = 'Revoked';
    
    @AuraEnabled(cacheable=true)
    public static CourseEditDataWrapper getCourseEditData(Id courseId) {
        CourseEditDataWrapper wrapper = new CourseEditDataWrapper();
        
        try {
            // Get course data
            Course__c course = [
                SELECT Id, Course_Name__c, Name, Category__c, Sub_Category__c, 
                       Description__c, Course_Objectives__c, Registration_Phone__c, Registration_Website__c, 
                       Status__c, Status_Selected__c, Special_Circumstances__c
                FROM Course__c 
                WHERE Id = :courseId
                LIMIT 1
            ];
            
            wrapper.course = course;
            
            // Check access
            wrapper.showNoAccessMessage = [
                SELECT Id 
                FROM CE_Action__c 
                WHERE Course__c = :courseId 
                AND Active__c = true 
                AND Action__c IN (:REVOKED, :DENIED)
            ].size() > 0;
            
            // Get content
            try {
                CE_Community_Content__mdt content = [
                    SELECT Edit_Course__c 
                    FROM CE_Community_Content__mdt
                    WHERE DeveloperName = 'Content' 
                    LIMIT 1
                ];
                wrapper.content = formatContentForHTML(content.Edit_Course__c);
            } catch (Exception e) {
                wrapper.content = '';
            }
            
            // Get sessions
            List<Session__c> sessions = [
                SELECT Id, Status__c, Start_Date__c, End_Date__c, Cost__c, 
                       Instructor_Name__c, Hours_Earned__c, Session_Type__c, 
                       Name, Time_Zone__c, RecordType.DeveloperName
                FROM Session__c 
                WHERE Course__c = :courseId 
                AND Status__c != '' 
                ORDER BY Start_Date__c ASC, Name ASC
            ];
            
            wrapper.publishedSessions = new List<SessionWrapper>();
            wrapper.draftSessions = new List<SessionWrapper>();
            wrapper.inactiveSessions = new List<SessionWrapper>();
            
            for (Session__c session : sessions) {
                SessionWrapper sw = new SessionWrapper(session);
                if (session.Status__c == PUBLISHED || session.Status__c == UNDER_REVIEW) {
                    wrapper.publishedSessions.add(sw);
                } else if (session.Status__c == DRAFT) {
                    wrapper.draftSessions.add(sw);
                } else {
                    wrapper.inactiveSessions.add(sw);
                }
            }
            
            wrapper.showPublishedSessions = !wrapper.publishedSessions.isEmpty();
            wrapper.showDraftSessions = !wrapper.draftSessions.isEmpty();
            wrapper.showInactiveSessions = !wrapper.inactiveSessions.isEmpty();
            
            // Check if last active session
            wrapper.isLastActiveSession = (wrapper.publishedSessions.size() == 1);
            
            // Status constants for frontend
            wrapper.statusConstants = new Map<String, String>{
                'COMPLETE' => COMPLETE,
                'DENIED' => DENIED,
                'DRAFT' => DRAFT,
                'INACTIVE' => INACTIVE,
                'PUBLISHED' => PUBLISHED,
                'UNDER_REVIEW' => UNDER_REVIEW,
                'REVOKED' => REVOKED
            };
            
        } catch (Exception e) {
            throw new AuraHandledException('Error loading course data: ' + e.getMessage());
        }
        
        return wrapper;
    }
    
    @AuraEnabled
    public static String publishCourseUpdates(Id courseId, String courseName, String courseSummary, 
                                             String description, String specialCircumstances, 
                                             String registrationPhone, String registrationWebsite, String status) {
        try {
            Course__c course = new Course__c(
                Id = courseId,
                Course_Name__c = courseName,
                Description__c = description,
                Special_Circumstances__c = specialCircumstances,
                Registration_Phone__c = registrationPhone,
                Registration_Website__c = registrationWebsite
            );
            
            // Set Course Summary only if provided (for new courses)
            if (String.isNotBlank(courseSummary)) {
                // Validate length on server side as well
                if (courseSummary.length() > 500) {
                    return 'ERROR: Course Objectives cannot exceed 500 characters.';
                }
                course.Course_Objectives__c = courseSummary;
            } else {
                return 'ERROR: Course Objectives are required.';
            }

            if (String.isBlank(description)) {
                return 'ERROR: Course Summary is required.';
            }
            if (description.length() > 500) {
                return 'ERROR: Course Summary cannot exceed 500 characters.';
            }
            
            // Update status if provided
            if (String.isNotBlank(status)) {
                course.Status_Selected__c = status;
            }
            
            // Validate registration phone
            if (String.isBlank(registrationPhone)) {
                return 'ERROR: A course registration contact telephone number is required.';
            }
            
            Database.update(course);
            return 'SUCCESS';
            
        } catch (DmlException e) {
            return 'ERROR: ' + e.getDmlMessage(0);
        } catch (Exception e) {
            return 'ERROR: ' + e.getMessage();
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getCourseStatusOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        options.add(new Map<String, String>{'label' => 'Draft', 'value' => DRAFT});
        options.add(new Map<String, String>{'label' => 'Published', 'value' => PUBLISHED});
        options.add(new Map<String, String>{'label' => 'Under Review', 'value' => UNDER_REVIEW});
        options.add(new Map<String, String>{'label' => 'Pending', 'value' => PENDING});
        options.add(new Map<String, String>{'label' => 'Inactive', 'value' => INACTIVE});
        return options;
    }
    
    @AuraEnabled
    public static void changeSessionStatus(Id sessionId, String status) {
        try {
            Session__c session = [
                SELECT Id, RecordType.DeveloperName 
                FROM Session__c 
                WHERE Id = :sessionId
                LIMIT 1
            ];
            
            session.Status_Selected__c = status;
            
            if (status == INACTIVE || status == PUBLISHED) {
                Date expirationDate = status == PUBLISHED ? System.today().addDays(364) : System.today();
                session.Expiration_Date__c = (session.RecordType.DeveloperName == 'On_Demand') ? expirationDate : null;
            }
            
            Database.update(session);
            
        } catch (Exception e) {
            throw new AuraHandledException('Error changing session status: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void deleteSession(Id sessionId) {
        try {
            Database.delete(sessionId);
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting session: ' + e.getMessage());
        }
    }
    
    // Helper method to format content HTML
    private static String formatContentForHTML(String content) {
        if (String.isBlank(content)) {
            return '';
        }
        // Basic HTML formatting - adjust based on your needs
        return content;
    }
    
    // Wrapper classes
    public class CourseEditDataWrapper {
        @AuraEnabled public Course__c course;
        @AuraEnabled public List<SessionWrapper> publishedSessions;
        @AuraEnabled public List<SessionWrapper> draftSessions;
        @AuraEnabled public List<SessionWrapper> inactiveSessions;
        @AuraEnabled public Boolean showPublishedSessions;
        @AuraEnabled public Boolean showDraftSessions;
        @AuraEnabled public Boolean showInactiveSessions;
        @AuraEnabled public Boolean showNoAccessMessage;
        @AuraEnabled public Boolean isLastActiveSession;
        @AuraEnabled public String content;
        @AuraEnabled public Map<String, String> statusConstants;
    }
    
    public class SessionWrapper {
        @AuraEnabled public Session__c session;
        @AuraEnabled public String startDT;
        @AuraEnabled public String endDT;
        
        public SessionWrapper(Session__c session) {
            this.session = session;
            
            if (session.Start_Date__c != null && session.End_Date__c != null && session.Time_Zone__c != null) {
                // Calculate timezone offset (simplified - you may need Utils.timeZoneOffset_hours)
                Integer offset = getTimeZoneOffset(session.Start_Date__c.date(), session.Time_Zone__c);
                DateTime startDT = session.Start_Date__c.addHours(offset);
                DateTime endDT = session.End_Date__c.addHours(offset);
                
                this.startDT = startDT.format('MM/dd/yyyy h:mm a');
                this.endDT = endDT.format('MM/dd/yyyy h:mm a');
            }
        }
    }
    
    // Simplified timezone offset calculation
    private static Integer getTimeZoneOffset(Date sessionDate, String timeZone) {
        // This is a simplified version - adjust based on your Utils.timeZoneOffset_hours implementation
        // For now, returning 0 - you may need to implement proper timezone conversion
        // TODO: Implement proper timezone offset calculation if Utils.timeZoneOffset_hours exists
        try {
            // If Utils class exists, use: return Utils.timeZoneOffset_hours(sessionDate, timeZone);
            return 0;
        } catch (Exception e) {
            return 0;
        }
    }
}