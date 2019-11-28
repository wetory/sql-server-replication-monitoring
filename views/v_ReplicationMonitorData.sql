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
)
SELECT
	s.PublicationId,
	s.AgentId,
	s.PublisherServer,
	s.PublisherDatabase,
	s.SubscriberServer,
	s.SubscriberDatabase,
	s.ReplicationType,
	MAX(md.status) AS ReplicationStatus,
	MAX(md.warning) AS ReplicationWarning,
	SUM(md.cur_latency) AS ReplicationLatency,
	MAX(md.last_distsync) AS LastSync
FROM Subscribers_CTE s
	INNER JOIN [distribution].[dbo].[MSreplication_monitordata] md ON md.publication_id = s.PublicationId AND md.agent_id = s.AgentId
GROUP BY 
	s.PublicationId,
	s.AgentId,
	s.PublisherServer,
	s.PublisherDatabase,
	s.SubscriberServer,
	s.SubscriberDatabase,
	s.ReplicationType

GO


