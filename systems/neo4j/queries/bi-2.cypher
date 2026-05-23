// Q2. Tag evolution
/*
:params { date: datetime('2012-06-01'), tagClass: 'MusicalArtist' }
*/
MATCH (tag:Tag)-[:HAS_TYPE]->(:TagClass {name: $tagClass})
// window 1
OPTIONAL MATCH (message1:Comment)-[:HAS_TAG]->(tag)
  WHERE $date <= message1.creation_date
    AND message1.creation_date < $date + duration({days: 100})
WITH tag, count(message1) AS countWindow1
// window 2
OPTIONAL MATCH (message2:Comment)-[:HAS_TAG]->(tag)
  WHERE $date + duration({days: 100}) <= message2.creation_date
    AND message2.creation_date < $date + duration({days: 200})
WITH
  tag,
  countWindow1,
  count(message2) AS countWindow2
RETURN
  tag.name,
  countWindow1,
  countWindow2,
  abs(countWindow1 - countWindow2) AS diff
ORDER BY
  diff DESC,
  tag.name ASC
LIMIT 100