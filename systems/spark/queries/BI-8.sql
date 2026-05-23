-- Use catalog demo and database mydb
USE demo.mydb;

-- BI query body
WITH Person_interested_in_Tag AS (
    SELECT person.id AS PersonId
      FROM person
      JOIN person_hasinterest_tag
        ON person_hasinterest_tag.person_id = person.id
      JOIN tag
        ON tag.id = person_hasinterest_tag.interest_id
       AND tag.name = 'Muammar_Gaddafi'
)
   , Person_Message_score AS (
    SELECT person.id AS PersonId
         , count(*) AS message_score
      FROM tag
      JOIN comment_hastag_tag
        ON comment_hastag_tag.tag_id = tag.id
      JOIN comment
        ON comment_hastag_tag.comment_id = comment.id
       AND comment.creation_date > TIMESTAMP '2011-01-01 00:00:00'
      -- Join edge table for creator id
      JOIN comment_hascreator_person
        ON comment_hascreator_person.comment_id = comment.id
      JOIN person
        ON person.id = comment_hascreator_person.person_id
     WHERE tag.name = 'Muammar_Gaddafi'
       AND comment.creation_date < TIMESTAMP '2012-12-25 00:00:00'
     GROUP BY person.id
)
   , Person_score AS (
    SELECT coalesce(Person_interested_in_Tag.PersonId, pms.PersonId) AS PersonId
         , (CASE WHEN Person_interested_in_Tag.PersonId IS NULL then 0 ELSE 100 END) -- scored from interest in the given tag
           + coalesce(pms.message_score, 0) AS score
      FROM Person_interested_in_Tag
           FULL JOIN Person_Message_score pms
                  ON Person_interested_in_Tag.PersonId = pms.PersonId
)
-- Spark SQL: quote aliases with backticks
SELECT p.PersonId AS `person.id`
     , p.score AS score
     , coalesce(sum(f.score), 0) AS friendsScore
  FROM Person_score p
  LEFT JOIN person_knows_person
    ON person_knows_person.person1_id = p.PersonId
  LEFT JOIN Person_score f -- the friend
    ON f.PersonId = person_knows_person.person2_id
 GROUP BY p.PersonId, p.score
 ORDER BY p.score + coalesce(sum(f.score), 0) DESC, p.PersonId ASC
 LIMIT 100;