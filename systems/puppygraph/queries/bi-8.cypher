// Parameters: $tag, $startDate, $endDate

MATCH (tag:tag {name: $tag})

// Score components for each person
MATCH (tag)<-[:person_hasinterest_tag]-(person:person)
WITH tag, person, 100 AS interestWeight

OPTIONAL MATCH (person)<-[:comment_hascreator_person]-(message:comment)-[:comment_hastag_tag]->(tag)
WHERE message.creation_date > datetime($startDate) AND message.creation_date < datetime($endDate)
WITH tag, person, interestWeight, count(message) AS commentScore

WITH tag, person, (interestWeight + commentScore) AS score

// Compute friendsScore
OPTIONAL MATCH (person)-[:person_knows_person]-(friend:person)
OPTIONAL MATCH (friend)<-[:person_hasinterest_tag]-(tag)
WITH person, score, friend, count(friend) AS friendInterestWeight

OPTIONAL MATCH (friend)<-[:comment_hascreator_person]-(message2:comment)-[:comment_hastag_tag]->(tag)
WHERE message2.creation_date > datetime($startDate) AND message2.creation_date < datetime($endDate)
WITH person, score, friendInterestWeight, count(message2) AS friendCommentScore

WITH person, score, (friendInterestWeight + friendCommentScore) AS friendScore

WITH person.id AS personId, score, sum(friendScore) AS friendsScore

RETURN personId, score, friendsScore
ORDER BY score + friendsScore DESC, personId ASC
LIMIT 100
