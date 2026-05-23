-- Use catalog demo and database mydb
USE demo.mydb;

-- BI query body
WITH
  subgraphA AS (
    SELECT DISTINCT person.id AS PersonId, comment.id AS MessageId
    FROM person
    -- Join comment_hascreator_person for creator
    JOIN comment_hascreator_person
      ON comment_hascreator_person.person_id = person.id
    JOIN comment
      ON comment.id = comment_hascreator_person.comment_id
     -- Spark DATE cast and compare
     AND CAST(comment.creation_date AS DATE) = DATE '2012-05-08'
    JOIN comment_hastag_tag
      ON comment_hastag_tag.comment_id = comment.id
    JOIN tag
      ON tag.id = comment_hastag_tag.tag_id
     AND tag.name = 'Adolf_Hitler'
  ),
  personA AS (
    SELECT
        subgraphA1.PersonId,
        count(DISTINCT subgraphA1.MessageId) AS cm,
        count(DISTINCT person_knows_person.person2_id) AS cp2
    FROM subgraphA subgraphA1
    LEFT JOIN person_knows_person
    ON person_knows_person.person1_id = subgraphA1.PersonId
    AND person_knows_person.person2_id IN (SELECT PersonId FROM subgraphA)
    GROUP BY subgraphA1.PersonId
    HAVING count(DISTINCT person_knows_person.person2_id) <= 4
    ORDER BY subgraphA1.PersonId ASC
  ),
  subgraphB AS (
    SELECT DISTINCT person.id AS PersonId, comment.id AS MessageId
    FROM person
    -- Join comment_hascreator_person for creator
    JOIN comment_hascreator_person
      ON comment_hascreator_person.person_id = person.id
    JOIN comment
      ON comment.id = comment_hascreator_person.comment_id
     AND CAST(comment.creation_date AS DATE) = DATE '2012-05-12'
    JOIN comment_hastag_tag
      ON comment_hastag_tag.comment_id = comment.id
    JOIN tag
      ON tag.id = comment_hastag_tag.tag_id
     AND tag.name = 'Hamid_Karzai'
  ),
  personB AS (
    SELECT
        subgraphB1.PersonId,
        count(DISTINCT subgraphB1.MessageId) AS cm,
        count(DISTINCT person_knows_person.person2_id) AS cp2
    FROM subgraphB subgraphB1
    LEFT JOIN person_knows_person
    ON person_knows_person.person1_id = subgraphB1.PersonId
    AND person_knows_person.person2_id IN (SELECT PersonId FROM subgraphB)
    GROUP BY subgraphB1.PersonId
    HAVING count(DISTINCT person_knows_person.person2_id) <= 4
    ORDER BY subgraphB1.PersonId ASC
  )
SELECT
    personA.PersonId AS PersonId,
    personA.cm AS messageCountA,
    personB.cm AS messageCountB
FROM personA
JOIN personB
  ON personB.PersonId = personA.PersonId
ORDER BY personA.cm + personB.cm DESC, PersonId ASC
LIMIT 20;