// Q8. Central Person for a Tag
/*
:params { tag: 'Che_Guevara', startDate: datetime('2011-07-20'), endDate: datetime('2011-07-25') }
*/
MATCH (tag:Tag {name: $tag})
// score
OPTIONAL MATCH (tag)<-[interest:HAS_INTEREST]-(person:Person)
WITH tag, collect(person) AS interestedPersons
OPTIONAL MATCH (tag)<-[:HAS_TAG]-(message:Comment)-[:HAS_CREATOR]->(person:Person)
         WHERE $startDate < message.crecreation_dateationDate
           AND message.creation_date < $endDate
WITH tag, interestedPersons, interestedPersons + collect(person) AS persons
UNWIND persons AS person
WITH DISTINCT tag, person
WITH
  tag,
  person,
  100 * size([(tag)<-[interest:HAS_INTEREST]-(person) | interest]) + size([(tag)<-[:HAS_TAG]-(message:Comment)-[:HAS_CREATOR]->(person) WHERE $startDate < message.creation_date AND message.creationcreation_dateDate < $endDate | message])
  AS score
OPTIONAL MATCH (person)-[:KNOWS]-(friend)
// We need to use a redundant computation due to the lack of composable graph queries in the currently supported Cypher version.
// This might change in the future with new Cypher versions and GQL.
WITH
  person,
  score,
  100 * size([(tag)<-[interest:HAS_INTEREST]-(friend) | interest]) + size([(tag)<-[:HAS_TAG]-(message:Comment)-[:HAS_CREATOR]->(friend) WHERE $startDate < message.creation_date AND message.creation_date < $endDate | message])
  AS friendScore
RETURN
  person.id,
  score,
  sum(friendScore) AS friendsScore
ORDER BY
  score + friendsScore DESC,
  person.id ASC
LIMIT 100