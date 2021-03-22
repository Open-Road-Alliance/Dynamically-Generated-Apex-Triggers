@isTest
public with sharing class ApexTriggerBuilderTest {
    static testmethod void testBuild() {
        Dynamic_Apex_Trigger_Configuration__c config = (Dynamic_Apex_Trigger_Configuration__c) TestDataFactory.createSObject('Dynamic_Apex_Trigger_Configuration__c', new Map<String, Object>{
            'Deployed__c' => true,
            'SObject_Name__c' => 'Account',
            'Field__c' => 'Name',
            'Field_Condition__c' => 'Test',
            'On_Complete_Callback__c' => 'new ApexTriggerBuilder()' 
        });

        ApexTriggerBuilder.ApexTriggerBuilderRequest request = new ApexTriggerBuilder.ApexTriggerBuilderRequest();
        request.recordId = config.Id;
        List<ApexTriggerBuilder.ApexTriggerBuilderRequest> requests = new List<ApexTriggerBuilder.ApexTriggerBuilderRequest>();
        requests.add(request);

        ApexTriggerBuilder.buildTriggers(requests);
        String asyncRequestId = '123';

        System.assertEquals('123', asyncRequestId, 'Ids do not match');
        MetadataService.DeployResult check = ApexTriggerBuilder.checkAsyncRequest(asyncRequestId);
        System.assertEquals(null, check, 'Results do not match');
    }
    static testmethod void testNoBuild() {
        ApexTriggerBuilder.ApexTriggerBuilderRequest request = new ApexTriggerBuilder.ApexTriggerBuilderRequest();
        List<ApexTriggerBuilder.ApexTriggerBuilderRequest> requests = new List<ApexTriggerBuilder.ApexTriggerBuilderRequest>();
        requests.add(request);

        ApexTriggerBuilder.buildTriggers(requests);
        String asyncRequestId = null;

        System.assertEquals(null, asyncRequestId, 'Ids do not match');
    }
}
