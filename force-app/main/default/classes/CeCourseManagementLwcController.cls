public with sharing class CeCourseManagementLwcController {
    
    private static final String DRAFT = 'Draft';
    private static final String INACTIVE = 'Inactive';
    private static final String PENDING = 'Pending';
    private static final String PUBLISHED = 'Published';
    private static final String UNDER_REVIEW = 'Under Review';
    
    @AuraEnabled(cacheable=true)
    public static CourseManagementDataWrapper getCourseManagementData() {
        CourseManagementDataWrapper wrapper = new CourseManagementDataWrapper();
        
        // Get account ID from current user
        User currentUser = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        wrapper.accountId = currentUser.AccountId;
        
        // Get course fee
        try {
            PricebookEntry pbe = [SELECT UnitPrice FROM PricebookEntry WHERE Name = 'CE Registry Course' LIMIT 1];
            wrapper.courseFee = pbe.UnitPrice;
        } catch (Exception e) {
            wrapper.courseFee = 00.00;
        }
        
        // Initialize lists
        wrapper.publishedCourses = new List<CourseWrapper>();
        wrapper.draftCourses = new List<CourseWrapper>();
        wrapper.inactiveCourses = new List<CourseWrapper>();
        wrapper.showNoSessionWarning = false;
        
        // Query courses
        List<Course__c> courses = [
            SELECT Id, Course_Name__c, Status__c, Name, 
                   Active_Sessions__c, Completed_Sessions__c, Total_Sessions__c
            FROM Course__c
            WHERE Contact__r.AccountId = :currentUser.AccountId 
            AND Status__c != NULL
            ORDER BY Course_Name__c ASC
        ];
        
        for (Course__c course : courses) {
            CourseWrapper cw = new CourseWrapper();
            cw.id = course.Id;
            cw.courseName = course.Course_Name__c;
            cw.status = course.Status__c;
            cw.courseId = course.Name;
            cw.activeSessions = course.Active_Sessions__c != null ? Integer.valueOf(course.Active_Sessions__c) : 0;
            cw.completedSessions = course.Completed_Sessions__c != null ? Integer.valueOf(course.Completed_Sessions__c) : 0;
            cw.totalSessions = course.Total_Sessions__c != null ? Integer.valueOf(course.Total_Sessions__c) : 0;
            
            // Add computed properties for template rendering
            cw.isPublishedOrUnderReview = (course.Status__c == PUBLISHED || course.Status__c == UNDER_REVIEW);
            cw.isPublishedOrPending = (course.Status__c == PUBLISHED || course.Status__c == PENDING);
            
            if (course.Status__c == PUBLISHED || course.Status__c == UNDER_REVIEW) {
                wrapper.publishedCourses.add(cw);
                if (cw.activeSessions == 0) {
                    wrapper.showNoSessionWarning = true;
                }
            } else if (course.Status__c == DRAFT) {
                wrapper.draftCourses.add(cw);
            } else {
                // All other statuses go to inactive (including INACTIVE, PENDING, and any other status)
                wrapper.inactiveCourses.add(cw);
                // Set isInactive to true for all courses in inactive list (not just status == INACTIVE)
                cw.isInactive = true;
            }
        }
        
        // Check for expiration notification
        try {
            Membership__c latestMembership = [
                SELECT Id, Is_Current__c, Expiration_Date__c
                FROM Membership__c
                WHERE Account__c = :currentUser.AccountId
                ORDER BY Expiration_Date__c DESC
                LIMIT 1
            ];
            
            if (latestMembership.Is_Current__c && latestMembership.Expiration_Date__c != null) {
                Integer daysBetween = System.today().daysBetween(latestMembership.Expiration_Date__c);
                if (daysBetween <= 14 && daysBetween >= 0) {
                    wrapper.showCourseExpiration = true;
                    wrapper.daysUntilExpiration = daysBetween;
                }
            }
        } catch (Exception e) {
            // No membership found or error
        }
        
        return wrapper;
    }
    
    @AuraEnabled
    public static void deleteCourse(Id courseId) {
        try {
            // Check if the record exists before attempting to delete
            List<Course__c> coursesToDelete = [
                SELECT Id 
                FROM Course__c 
                WHERE Id = :courseId 
                LIMIT 1
            ];
            
            if (coursesToDelete.isEmpty()) {
                // Record doesn't exist or already deleted - return silently or throw specific error
                throw new AuraHandledException('Course not found or already deleted');
            }
            
            Database.delete(courseId);
        } catch (DmlException e) {
            // Handle specific error cases
            if (e.getMessage().contains('ENTITY_IS_DELETED')) {
                // Record already deleted, treat as success
                return;
            }
            throw new AuraHandledException('Error deleting course: ' + e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting course: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void changeCourseStatus(Id courseId, String status) {
        try {
            Course__c course = new Course__c(
                Id = courseId,
                Status_Selected__c = status
            );
            Database.upsert(course);
        } catch (DmlException e) {
            throw new AuraHandledException('Error updating course status: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Account getAccountPolicies(Id accountId) {
        return [
            SELECT Cancellation_Details__c, ADA_Details__c, Grievance_Process__c, 
                   Conflict_of_Interest__c, Registration_Instructions__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
    }
    
    // Wrapper classes
    public class CourseManagementDataWrapper {
        @AuraEnabled public Id accountId;
        @AuraEnabled public Decimal courseFee;
        @AuraEnabled public List<CourseWrapper> publishedCourses;
        @AuraEnabled public List<CourseWrapper> draftCourses;
        @AuraEnabled public List<CourseWrapper> inactiveCourses;
        @AuraEnabled public Boolean showNoSessionWarning;
        @AuraEnabled public Boolean showCourseExpiration;
        @AuraEnabled public Integer daysUntilExpiration;
    }
    
    public class CourseWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String courseName;
        @AuraEnabled public String status;
        @AuraEnabled public String courseId;
        @AuraEnabled public Integer activeSessions;
        @AuraEnabled public Integer completedSessions;
        @AuraEnabled public Integer totalSessions;
        @AuraEnabled public Boolean isPublishedOrUnderReview;
        @AuraEnabled public Boolean isPublishedOrPending;
        @AuraEnabled public Boolean isInactive;
    }
}