-- Use catalog demo and database mydb
USE demo.mydb;

-- BI query body
WITH detail AS (
    SELECT cp.person_id AS CreatorPersonId
         , sum(coalesce(Cs.c, 0)) AS replyCount
         , sum(coalesce(Plm.c, 0)) AS likeCount
         , count(c.id) AS messageCount
    FROM tag t
    -- Match tags on comment
    JOIN comment_hastag_tag cht ON cht.tag_id = t.id
    JOIN comment c ON c.id = cht.comment_id
    -- Creator via edge table
    JOIN comment_hascreator_person cp ON cp.comment_id = c.id
    -- Reply count for comment
    -- comment2_id is parent comment in comment_replyof_comment
    LEFT JOIN (
        SELECT comment2_id AS id, count(*) AS c
        FROM comment_replyof_comment
        GROUP BY comment2_id
    ) Cs ON Cs.id = c.id
    -- Like count for comment
    LEFT JOIN (
        SELECT comment_id AS id, count(*) AS c
        FROM person_likes_comment
        GROUP BY comment_id
    ) Plm ON Plm.id = c.id
    WHERE t.name = 'Augustine_of_Hippo'
    GROUP BY cp.person_id
)
-- Spark SQL: quote aliases with backticks
SELECT CreatorPersonId AS `person.id`
     , CAST(replyCount AS BIGINT) AS replyCount
     , CAST(likeCount AS BIGINT) AS likeCount
     , CAST(messageCount AS BIGINT) AS messageCount
     , CAST(messageCount + (2 * replyCount) + (10 * likeCount) AS BIGINT) AS score
FROM detail
ORDER BY score DESC, CreatorPersonId ASC
LIMIT 100;