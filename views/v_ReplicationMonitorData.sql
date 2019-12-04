USE [distribution]
GO
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[v_ReplicationMonitorData]
AS
WITH Subscribers_CTE (
	PublicationId,
	PublisherServer,
	PublisherDatabase,
	SubscriberServer,
	SubscriberDatabase,
	ReplicationType,
	AgentId
) AS (
	SELECT DISTINCT
		ms.publication_id,
		sp.name,
		ms.publisher_db,
		ss.name,
		ms.subscriber_db,
		ms.subscription_type,
		ms.agent_id
	FROM [distribution].[dbo].[MSsubscriptions] ms
		INNER JOIN [master].[sys].[servers] sp ON ms.publisher_id = sp.server_id
		INNER JOIN [master].[sys].[servers] ss ON ms.subscriber_id = ss.server_id
	WHERE ms.subscriber_db <> 'virtual'
), AgentsStates_CTE (
	PublisherServer,
	PublisherDatabase,
	SnapshotAgent,
	LogReaderAgent,
	DistributionAgent,
	MergeAgent,
	QueueReaderAgent
) AS (
	SELECT * FROM
	(	
		SELECT 
			publisher, 
			publisher_db,
			CASE agent_type
				WHEN 1 THEN 'Snapshot'
				WHEN 2 THEN 'LogReader'
				WHEN 3 THEN 'Distribution'
				WHEN 4 THEN 'Merge'
				WHEN 9 THEN 'QueueReader'
			END AS agent_type,
			[status]
		FROM [distribution].[dbo].[MSreplication_monitordata]
	) AS SourceTable PIVOT (
		MAX([status]) FOR agent_type IN ([Snapshot], [LogReader], [Distribution], [Merge], [QueueReader])
	) AS PivotTable
)
SELECT
	s.PublicationId,
	s.AgentId,
	s.PublisherServer,
	s.PublisherDatabase,
	s.SubscriberServer,
	s.SubscriberDatabase,
	s.ReplicationType,
	MAX(a.SnapshotAgent) AS SnapshotAgentState,
	MAX(a.LogReaderAgent) AS LogReaderAgentState,
	MAX(a.DistributionAgent) AS DistributionAgentState,
	MAX(a.MergeAgent) AS MergeAgentState,
	MAX(a.QueueReaderAgent) AS QueueReaderAgentState,
	MAX(md.status) AS ReplicationStatus,
	MAX(md.warning) AS ReplicationWarning,
	SUM(md.cur_latency) AS ReplicationLatency,
	MAX(md.last_distsync) AS LastSync
FROM Subscribers_CTE s
	INNER JOIN [distribution].[dbo].[MSreplication_monitordata] md ON md.publication_id = s.PublicationId AND md.agent_id = s.AgentId
	INNER JOIN AgentsStates_CTE a ON a.PublisherServer = s.PublisherServer AND a.PublisherDatabase = s.PublisherDatabase
GROUP BY 
	s.PublicationId,
	s.AgentId,
	s.PublisherServer,
	s.PublisherDatabase,
	s.SubscriberServer,
	s.SubscriberDatabase,
	s.ReplicationType
GO


