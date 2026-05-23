// Q13. Zombies in a country
/*
:params { country: 'France', endDate: '2013-01-01' }
*/
MATCH (country:place {name: $country})<-[:place_ispartof_place]-(:place)<-[:person_islocatedin_city]-(zombie:person)
WHERE zombie.creation_date < datetime($endDate)
WITH country, zombie
OPTIONAL MATCH (zombie)<-[:comment_hascreator_person]-(message:comment)
WHERE message.creation_date < datetime($endDate)
WITH
  country,
  zombie,
  count(message) AS messageCount
WITH
  country,
  zombie,
  12 * (datetime($endDate).year  - zombie.creation_date.year )
     + (datetime($endDate).month - zombie.creation_date.month)
     + 1 AS months,
  messageCount
WHERE messageCount / months < 1
WITH
  country,
  collect(zombie) AS zombies,
  collect(zombie.id) AS zombie_ids
UNWIND zombies AS zombie
OPTIONAL MATCH
  (zombie)<-[:comment_hascreator_person]-(message:comment)<-[:person_likes_comment]-(likerZombie:person)
WHERE likerZombie.id IN zombie_ids
WITH
  zombie,
  count(likerZombie) AS zombieLikeCount
OPTIONAL MATCH
  (zombie)<-[:comment_hascreator_person]-(message:comment)<-[:person_likes_comment]-(likerPerson:person)
WHERE likerPerson.creation_date < datetime($endDate)
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