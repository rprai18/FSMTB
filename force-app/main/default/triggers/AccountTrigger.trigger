trigger AccountTrigger on Account (before insert, before update, after update) {
	new AccountTriggerHandler().run();
}