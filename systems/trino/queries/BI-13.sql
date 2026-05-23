WITH Zombies AS (
    SELECT person.id AS zombieid
      FROM place country
      JOIN place_ispartof_place
        ON place_ispartof_place.place2_id = country.id
      JOIN place city
        ON city.id = place_ispartof_place.place1_id
      JOIN person_islocatedin_city
        ON person_islocatedin_city.city_id = city.id
      JOIN person
        ON person.id = person_islocatedin_city.person_id
      -- Message view for LEFT JOIN compatibility
      LEFT JOIN (
          SELECT c.id AS MessageId
               , cp.person_id AS CreatorPersonId
               , c.creation_date
            FROM comment c
            JOIN comment_hascreator_person cp 
              ON cp.comment_id = c.id
      ) Message
         ON person.id = Message.CreatorPersonId
        AND Message.creation_date BETWEEN person.creation_date AND TIMESTAMP '2011-12-25 00:00:00'
     WHERE country.name = 'Brazil'
       AND person.creation_date < TIMESTAMP '2011-12-25 00:00:00'
     GROUP BY person.id, person.creation_date
    HAVING count(Message.MessageId) < 12*extract(YEAR FROM TIMESTAMP '2011-12-25 00:00:00') + extract(MONTH FROM TIMESTAMP '2011-12-25 00:00:00')
                                    - (12*extract(YEAR FROM person.creation_date) + extract(MONTH FROM person.creation_date))
                                    + 1
)
SELECT Z.zombieid AS "zombie.id"
     , coalesce(t.zombieLikeCount, 0) AS zombieLikeCount
     , coalesce(t.totalLikeCount, 0) AS totalLikeCount
     -- Trino: CAST(... AS DOUBLE) instead of ::float
     , CASE WHEN t.totalLikeCount > 0 THEN CAST(t.zombieLikeCount AS DOUBLE)/t.totalLikeCount ELSE 0 END AS zombieScore
  FROM Zombies Z LEFT JOIN (
    SELECT Z.zombieid, count(*) as totalLikeCount, sum(case when exists (SELECT 1 FROM Zombies ZL WHERE ZL.zombieid = p.id) then 1 else 0 end) AS zombieLikeCount
    -- Implicit comma join; comment_hascreator_person for creator
    FROM person p, person_likes_comment plm, comment m, comment_hascreator_person m_cp, Zombies Z
    WHERE Z.zombieid = m_cp.person_id 
      AND m_cp.comment_id = m.id
      AND p.creation_date < TIMESTAMP '2011-12-25 00:00:00'
      AND p.id = plm.person_id 
      AND m.id = plm.comment_id
    GROUP BY Z.zombieid
  ) t ON (Z.zombieid = t.zombieid)
 ORDER BY zombieScore DESC, Z.zombieid
 LIMIT 100
;