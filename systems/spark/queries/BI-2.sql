-- Use catalog demo and database mydb
USE demo.mydb;

-- BI query body
WITH 
MyTag AS (
    SELECT t.id AS id, t.name AS name
    FROM tagclass tc
    JOIN tag_hastype_tagclass tht ON tht.tagclass_id = tc.id
    JOIN tag t ON t.id = tht.tag_id
    WHERE tc.name = 'Person'
),
detail AS (
    SELECT t.id AS TagId
         -- Spark: INTERVAL 100 DAYS
         , count(CASE WHEN c.creation_date <  TIMESTAMP '2010-12-25 00:00:00' + INTERVAL 100 DAYS THEN c.id ELSE NULL END) AS countMonth1
         , count(CASE WHEN c.creation_date >= TIMESTAMP '2010-12-25 00:00:00' + INTERVAL 100 DAYS THEN c.id ELSE NULL END) AS countMonth2
    FROM MyTag t
    JOIN comment_hastag_tag cht ON cht.tag_id = t.id
    JOIN comment c ON c.id = cht.comment_id
         AND c.creation_date >= TIMESTAMP '2010-12-25 00:00:00'
         AND c.creation_date <  TIMESTAMP '2010-12-25 00:00:00' + INTERVAL 200 DAYS
    GROUP BY t.id
)
SELECT t.name AS `tag.name`
     , coalesce(countMonth1, 0) AS countMonth1
     , coalesce(countMonth2, 0) AS countMonth2
     , abs(coalesce(countMonth1, 0) - coalesce(countMonth2, 0)) AS diff
FROM MyTag t 
LEFT JOIN detail ON t.id = detail.TagId
ORDER BY diff DESC, t.name ASC
LIMIT 100;