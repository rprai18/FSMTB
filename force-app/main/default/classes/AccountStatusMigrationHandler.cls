/**
 * Migration handler for populating initial Account Status values
 * This class migrates existing Status__c formula values to new status fields
 * 
 * Usage: Run in Developer Console as Anonymous Apex:
 * AccountStatusMigrationHandler.migrateAllAccounts();
 * 
 * Or migrate specific accounts:
 * AccountStatusMigrationHandler.migrateAccounts(new List<Id>{'001...', '001...'});
 */
public with sharing class AccountStatusMigrationHandler {
    
    /**
     * Migrate all accounts - processes in batches of 200
     */
    public static void migrateAllAccounts() {
        List<Id> allAccountIds = new List<Id>();
        
        // Get all Account IDs (CE Provider and MT Verify record types if needed)
        for (Account acc : [SELECT Id FROM Account LIMIT 10000]) {
            allAccountIds.add(acc.Id);
        }
        
        System.debug('Total accounts to migrate: ' + allAccountIds.size());
        
        // Process in batches
        Integer batchSize = 200;
        for (Integer i = 0; i < allAccountIds.size(); i += batchSize) {
            Integer endIndex = Math.min(i + batchSize, allAccountIds.size());
            List<Id> batchIds = new List<Id>();
            
            for (Integer j = i; j < endIndex; j++) {
                batchIds.add(allAccountIds[j]);
            }
            
            System.debug('Migrating batch: ' + (i/batchSize + 1) + ', Accounts: ' + batchIds.size());
            AccountTriggerHandler.recalculateAllAccountStatuses(batchIds);
        }
        
        System.debug('Migration completed for all accounts');
    }
    
    /**
     * Migrate specific accounts by ID
     */
    public static void migrateAccounts(List<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            System.debug('No account IDs provided for migration');
            return;
        }
        
        System.debug('Migrating ' + accountIds.size() + ' accounts');
        AccountTriggerHandler.recalculateAllAccountStatuses(accountIds);
        System.debug('Migration completed');
    }
    
    /**
     * Migrate accounts by RecordType
     */
    public static void migrateAccountsByRecordType(String recordTypeDeveloperName) {
        List<Id> accountIds = new List<Id>();
        
        for (Account acc : [
            SELECT Id 
            FROM Account 
            WHERE RecordType.DeveloperName = :recordTypeDeveloperName
            LIMIT 10000
        ]) {
            accountIds.add(acc.Id);
        }
        
        System.debug('Found ' + accountIds.size() + ' accounts with RecordType: ' + recordTypeDeveloperName);
        
        if (!accountIds.isEmpty()) {
            AccountStatusHandler.recalculateAllAccountStatuses(accountIds);
        }
    }
    
    /**
     * Verify migration by comparing old Status__c with new fields
     * Run this after migration to verify data
     */
    public static void verifyMigration(Integer sampleSize) {
        Integer count = sampleSize != null ? sampleSize : 20;
        
        List<Account> accounts = [
            SELECT Id, Name, RecordType.DeveloperName, Status__c,
                   Membership_Status__c, Registration_Status__c, 
                   Registration_Status_Date__c, Registration_Status_Flag__c,
                   Current_Active_Action_Status__c,
                   Membership_Expiration_Date__c, Allow_Renewal__c,
                   Survey_Total_Happy__c
            FROM Account
            LIMIT :count
        ];
        
        System.debug('=== Migration Verification Sample ===');
        System.debug('Total accounts checked: ' + accounts.size());
        
        for (Account acc : accounts) {
            System.debug('---');
            System.debug('Account: ' + acc.Name + ' (Id: ' + acc.Id + ')');
            System.debug('RecordType: ' + acc.RecordType.DeveloperName);
            System.debug('Old Status__c: ' + acc.Status__c);
            System.debug('New Membership_Status__c: ' + acc.Membership_Status__c);
            System.debug('New Registration_Status__c: ' + acc.Registration_Status__c);
            System.debug('Registration_Status_Date__c: ' + acc.Registration_Status_Date__c);
            System.debug('Registration_Status_Flag__c: ' + acc.Registration_Status_Flag__c);
            System.debug('Current_Active_Action_Status__c: ' + acc.Current_Active_Action_Status__c);
            System.debug('Membership_Expiration_Date__c: ' + acc.Membership_Expiration_Date__c);
            System.debug('Survey_Total_Happy__c: ' + acc.Survey_Total_Happy__c);
        }
        
        System.debug('=== End Verification ===');
    }
}

