// Q13. Zombies in a country
/*
:params { country: 'France', endDate: datetime('2013-01-01') }
*/
MATCH (country:Place {name: $country})<-[:IS_PART_OF]-(:Place)<-[:IS_LOCATED_IN]-(zombie:Person)
WHERE zombie.creation_date < $endDate
WITH country, zombie
OPTIONAL MATCH (zombie)<-[:HAS_CREATOR]-(message:Comment)
WHERE message.creation_date < $endDate
WITH
  country,
  zombie,
  count(message) AS messageCount
WITH
  country,
  zombie,
  12 * ($endDate.year  - zombie.creation_date.year )
     + ($endDate.month - zombie.creation_date.month)
     + 1 AS months,
  messageCount
WHERE messageCount / months < 1
WITH
  country,
  collect(zombie) AS zombies
UNWIND zombies AS zombie
OPTIONAL MATCH
  (zombie)<-[:HAS_CREATOR]-(message:Comment)<-[:LIKES]-(likerZombie:Person)
WHERE likerZombie IN zombies
WITH
  zombie,
  count(likerZombie) AS zombieLikeCount
OPTIONAL MATCH
  (zombie)<-[:HAS_CREATOR]-(message:Comment)<-[:LIKES]-(likerPerson:Person)
WHERE likerPerson.creation_date < $endDate
WITH
  zombie,
  zombieLikeCount,
  count(likerPerson) AS totalLikeCount
RETURN
  zombie.id,
  zombieLikeCount,
  totalLikeCount,
  CASE totalLikeCount
    WHEN 0 THEN 0.0
    ELSE zombieLikeCount / toFloat(totalLikeCount)
  END AS zombieScore
ORDER BY
  zombieScore DESC,
  zombie.id ASC
LIMIT 100