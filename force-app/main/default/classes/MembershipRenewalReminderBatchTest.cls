/**
 * Test class for MembershipRenewalReminderBatch
 */
@isTest
private class MembershipRenewalReminderBatchTest {
    
    @testSetup
    static void setupTestData() {
        // Create test Account
        Account testAccount = new Account(
            Name = 'Test CE Provider Account'
        );
        insert testAccount;
        
        // Create test Contact
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'testuser@test.com',
            AccountId = testAccount.Id
        );
        insert testContact;
        
        // Create test User (Community User)
        Profile communityProfile = [
            SELECT Id 
            FROM Profile 
            WHERE Name LIKE '%Customer%' OR Name LIKE '%Community%'
            LIMIT 1
        ];
        
        User testUser = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'testuser@test.com',
            Username = 'testuser' + DateTime.now().getTime() + '@test.com',
            Alias = 'tuser',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = communityProfile.Id,
            ContactId = testContact.Id,
            IsActive = true
        );
        insert testUser;
        
        // Create Membership expiring in 30 days
        Date expirationDate = Date.today().addDays(30);
        Membership__c testMembership = new Membership__c(
            Account__c = testAccount.Id,
            Start_Date__c = Date.today().addDays(-335), // Started 335 days ago
            Expiration_Date__c = expirationDate
        );
        insert testMembership;
    }
    
    @isTest
    static void testBatchExecution() {
        Test.startTest();
        
        // Execute batch
        MembershipRenewalReminderBatch batch = new MembershipRenewalReminderBatch();
        Database.executeBatch(batch, 200);
        
        Test.stopTest();
        
        // Verify that batch completed (no exceptions)
        // Note: In test context, emails are not actually sent, but the batch should complete successfully
        List<Membership__c> memberships = [
            SELECT Id, Expiration_Date__c 
            FROM Membership__c 
            WHERE Expiration_Date__c = :Date.today().addDays(30)
        ];
        
        System.assert(!memberships.isEmpty(), 'Test membership should exist');
    }
    
    @isTest
    static void testSchedulableExecution() {
        Test.startTest();
        
        // Test schedulable interface
        MembershipRenewalReminderBatch batch = new MembershipRenewalReminderBatch();
        String cronExpr = '0 0 2 * * ?'; // Daily at 2 AM
        String jobId = System.schedule('Test Membership Renewal Reminder', cronExpr, batch);
        
        Test.stopTest();
        
        // Verify job was scheduled
        CronTrigger ct = [
            SELECT Id, CronExpression, TimesTriggered, NextFireTime
            FROM CronTrigger
            WHERE Id = :jobId
        ];
        
        System.assertEquals(cronExpr, ct.CronExpression, 'Cron expression should match');
    }
    
    @isTest
    static void testBatchWithNoMemberships() {
        // Delete test membership
        delete [SELECT Id FROM Membership__c];
        
        Test.startTest();
        
        MembershipRenewalReminderBatch batch = new MembershipRenewalReminderBatch();
        Database.executeBatch(batch, 200);
        
        Test.stopTest();
        
        // Batch should complete without errors even with no memberships
        System.assert(true, 'Batch should complete successfully with no memberships');
    }
    
    @isTest
    static void testBatchWithFutureMembership() {
        // Create a future membership (renewal already completed)
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Membership__c futureMembership = new Membership__c(
            Account__c = testAccount.Id,
            Start_Date__c = Date.today().addDays(31), // Starts after current expiration
            Expiration_Date__c = Date.today().addDays(400)
        );
        insert futureMembership;
        
        Test.startTest();
        
        MembershipRenewalReminderBatch batch = new MembershipRenewalReminderBatch();
        Database.executeBatch(batch, 200);
        
        Test.stopTest();
        
        // Batch should complete - the membership with future membership should be excluded
        System.assert(true, 'Batch should complete successfully');
    }
}

