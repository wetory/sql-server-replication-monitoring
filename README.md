# SQL Server Replication Monitoring
Simple solution for regular checking of replication subscriptions based on querying system tables on distribution server. Require Database Mail to notify you everytime some subscription is not running or containing any warning. More detailed info within [documentation file](docs/SQL%20Server%20Replication%20Monitoring%20-%20documentation.pdf).

Table of contents:
  * [Technical preview](#technical-preview)
  * [Deployment](#deployment)
  * [Execution of stored procedures](#execution-of-stored-procedures)
  * [Possible problems](#possible-problems)
  * [Versions](#versions)

## Technical preview

Whole solution consist of one view and one stored procedure created in distribution database. Procedure can be called directly or from SQL Agent job steps. View is just for simplyfying code as it contains longer SELECT statement querying system tables in distribution database. Stored procedure is querying this view and deciding based on seuncribers state or warnings if to rise alert or not. By default you can see not properly working subscriptions in result set.  

*	**v_ReplicationMonitorData** – querying systems table
*	**usp_ReplicationMonitor** – logic to decide if rise alert based on monitoring data from above view

For regular checking SQL Agent job is created, it only contains one step for calling above mentioned stored proceedure and send notification to given emails via given database mail profile. You have to properly configure Database Mail if you want to use notification on regular basis. 

Nice article about configuration of Database Mail can be found on [Brent Ozar's website](https://www.brentozar.com/blitz/database-mail-configuration/).

## Deployment 
Only thing you have to do is to copy [deplyment script](SQL%20Server%20Replication%20Monitoring.sql). Open it in SQL Server Management Studio and run it against SQL Server instance you are connected to or use multiquery from Registered Servers. Running script using multi-query is especially benefical when you are using multiple distribution servers, you will avoid unnecesarry clicking when connecting to every replica and running one by one. 

Just set script run variables to match your environment needs. Find folowing code at the beginning of deployment script. You have to specify recipients of email notifications and name of your configured database mail profile.

```
SET @AlertRecipients = '<your email addresses here>'		
SET @DbMailProfile = '<your database mail profile here>'
```

### Direct messages

After proper execution you can check messages for detailed steps which have been done over instance and also for possible related error messages.

### Views

You can see new view [dbo.v_ReplicationMonitorData](views/v_ReplicationMonitorData.sql) created in dstribution database.

### Stored procedures

You can see one new stored procedure [dbo.usp_ReplicationMonitor](stored%20procedures/usp_ReplicationMonitor.sql) in dstribution database.

### SQL Agent jobs

You can see SQL Agent job created with name "Warning: Replication Health" containing one step for calling stored procedure [dbo.usp_ReplicationMonitor](stored%20procedures/usp_ReplicationMonitor.sql). Just kee in mind it is created without any schedule so you have to pick what fits best for your requirements.

## Execution of stored procedures

OK so you are all set now and you can start enjoying new stored procedure. You can use it just for manual check if all subscribers using your distribution servers are working. Or you can use it in your further T-SQL development where replication state plays major role. What is prepared for you is using this procedure in SQL Agent job informing you where there is some problem. Procedure also producing resultset formatted as HTML table element containing data. HTML table from output parameter @p_HTMLTableResults can be used in HTML context for example in notification email.

### Parameters

Stored procedure has some input paramaters that are optional to use and has their default values.

Input:
*	**@p_SuppressResults** *BIT* – You can use it for supressing resultset.Useful when you just want to check if alert state happening but no more information needed. By default set to 0.
Output:
*	**@p_HTMLTableResults** *NVARCHAR(MAX)* – This parameter contains resultset formatted as HTML table. Use it in HTML context to directly put results into website or HTML formatted email message.
*	**@p_RiseAlert** *BIT*  - This parameter is holding flag if some alert situation is happening with subscriptions. You can use it to pass this flag out of stored procedure and use it in your firther program workflow.


### Simple run for checking actual state (no parameters)
```
EXEC [distribution].[dbo].[usp_ReplicationMonitor]
```

### Check if there is some problem (output parameter @p_RiseAlert)
```
DECLARE @RiseAlert BIT	
DECLARE @ResultTable NVARCHAR(MAX)

EXEC [distribution].[dbo].[usp_ReplicationMonitor] 
  @p_RiseAlert = @RiseAlert OUTPUT,
  @p_HTMLTableResults = @ResultTable OUTPUT		

SELECT @RiseAlert
```

### Supress result set outcome (parameter @p_SuppressResults set to 1)
```
DECLARE @RiseAlert BIT	
DECLARE @ResultTable NVARCHAR(MAX)

EXEC [distribution].[dbo].[usp_ReplicationMonitor] 
  @p_SuppressResults = 1, 
  @p_RiseAlert = @RiseAlert OUTPUT,  
  @p_HTMLTableResults = @ResultTable OUTPUT		

SELECT @RiseAlert
```
You just don't get any result set if there is some not properly working subscriptions. Useful for pure programatic use.

### Results

Stored procedure will return table with not properly working subscriptions in your replication setup. Then you can focus on solving problems causing this state. Results can be supressed by using *@p_SuppressResults* parameter. In such case just use value of output parameter in your workflow and do some reaction on this state.

Use content of *@p_HTMLTableResults* to insert HTML table formatted resultset in some HTML context.

## Possible problems
There was testing of the solution for debugging and tuning purposes and all known problems has been fixed already, but as everything also this script can cause some issues in different environments. 

I’m assuming only following possible issues:
* problems with not properly working Database Mail - if you are using SQL Server 2016 there is [known bug](https://support.microsoft.com/en-hk/help/3186435/sql-server-2016-database-mail-doesn-t-work-when-net-framework-3-5) fixed in CUs 
* [Failed to initialize sqlcmd library with error number -2147467259](https://blog.sqlauthority.com/2015/06/13/sql-server-login-failed-for-user-nt-authorityanonymous-logon/)

## Versions
* v1.0 - first sharable tested solution major bugs fixed

## Reporting issues

Please report all found issues, current version of the solution is the first one and require some debugging to be “perfect”.

*	Use GitHub issues channel


