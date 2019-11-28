# SQL Server Database Restore
Standardized database restore, doing some of pre-restore checks and post-restore configurations with restored databse. Doing also refresh of Availability Group databases, means restores into databases that are part of Availability Group and joining them back. More detailed info within [documentation file](docs/SQL%20Server%20Database%20Restore%20-%20documentation.pdf).

Table of contents:
  * [Technical preview](#technical-preview)
  * [Deployment](#deployment)
  * [Execution of stored procedures](#execution-of-stored-procedures)
  * [Possible problems](#possible-problems)
  * [Versions](#versions)

## Technical preview

Whole solution consist of two stored procedures, that can be called directly or from SQL Agent job steps. One procedure is needed for all restore scenarios, and another only needed on Availability Group (only AG in further writting) secondary replicas to be able to join database to AG. 

*	RestoreDatabase – perform every restore
*	AddDatabaseOnSecondary – only needed on secondary replicas

Both procedures using pure T-SQL approach, I know similar operations can be performed by PowerShell and maybe more efficiently, but I like T-SQL way. 

Both procedures cooperating with Ola Halengreen’s maintenance solution procedures (visit here for more details https://ola.hallengren.com/), using its CommandLog table for tracking operations done during execution and CommandExecute for executing commands wtihin script. Both table and procedure is created during deployment and you are informed about it.

## Deployment 

Only thing you have to do is to copy [deplyment script](SQL%20Server%20Database%20Restore.sql). Copy script to SQL Server Management Studio and run it aganst SQL Server instance you are connected to or use multiquery from Registered Servers. Running script using multi-query is especially benefical when creating procedures on AG replicas, you will avoid unnecesarry clicking when connecting to every replica and running one by one. 

### Direct messages

After proper execution you can check messages for detailed steps which have been done over instance and also for possible related error messages.

### Stored procedures

You can see two new stored procedures in master database + CommandExecute procedure from Ola Halengreen (if not there already)

### Tables

There is one table created within deployment – CommandLog if it already did not exist before deployment. It is borrowed from Ola’s maintenance solution. If you are using Ola Halengreen’s maitnenance solution you can just see new records related to restores in this table.

## Execution of stored procedures

OK so you are all set now and you can start enjoying new stored procedures. You can use RestoreDatabase procedure to make common restore to standalone SQL Server database or you can use it to refresh database that is part of Availability Group

For detailed description of what is each procedure doing behind the scenes look into [documentation file](docs/SQL%20Server%20Database%20Restore%20-%20documentation.pdf) or go through messages after its execution. 

### Restore of database and set up autogrowth based on model database*
```
EXEC [master].[dbo].[RestoreDatabase]
@BackupFile = N'\\Path\To\BackupFile\Backup.bak',
@Database = N'TestDB',
@CheckModel = 'Y', 
@LogToTable = 'Y'
```
*@CheckModel parameter available since v1.2

### Restore of database that is joined in Availability Group
```
EXEC [master].[dbo].[RestoreDatabase]
@BackupFile = N'\\Path\To\BackupFile\Backup.bak',
@Database = N'TestDB',
@AvailabilityGroup = N'AvailabilityGroupName',
@SharedFolder = N'\\Path\To\AGShare',
@LogToTable = 'Y'
```

### Executing stored procedure AddDatabaseOnSecondary
Folowing command is constructed automatically within RestoreDatabase execution but you can  call procedure directly if you want:
```
EXEC [master].[dbo].[AddDatabaseOnSecondary]
@FullBackupFile = N'\\Path\To\BackupFile\FullBackup.bak',
@TlogBackupFile = N'\\Path\To\BackupFile\TlogBackup.trn',
@Database = N'TestDB',
@AvailabilityGroup = N'AvailabilityGroupName',
@LogToTable = 'Y'		
```

### Messages

Stored procedures are informing you via messages about its execution steps in pretty detailed info messages. Also you can find possible error desctiptions in messages after execution failed.

## Possible problems
There was testing of the solution ongoing for several weeks for debugging and tuning purposes and all known problems has been fixed already, but as everything also this script can cause some issues in different environments. 

I’m assuming only following possible issues:
* problems with accessing secondary replica via linked server - [Login failed for User ‘NT AUTHORITY\ANONYMOUS LOGON’](https://blog.sqlauthority.com/2015/06/13/sql-server-login-failed-for-user-nt-authorityanonymous-logon/)
*	When executing from SQL Agent job, ensure that account that is used for execution has sufficient permissions, especially in case restoring database into Avaialability Group as there are actions done on all secondary replicas.

And some other possible problems can be related to OH stuff in the solution so, please be so kind and try to check this FAQ https://ola.hallengren.com/frequently-asked-questions.html first before asking me directly.

## Versions
* v1.1 - first sharable tested solution major bugs fixed
* v1.2 - added possiblity to set autogrowth for restored database based on model database settings (RestoreDatabase stored procedure)

## Reporting issues

Please report all found issues, current version of the solution is the first one and require some debugging to be “perfect”.

*	Use GitHub issues channel


