// Q2. Tag evolution
/*
:params {date: '2012-06-01', tagClass: 'MusicalArtist' }
*/
MATCH (tag:tag)-[:tag_hastype_tagclass]->(:tagclass {name: $tagClass})
// window 1
OPTIONAL MATCH (message1:comment)-[:comment_hastag_tag]->(tag)
  WHERE datetime($date) <= message1.creation_date
    AND message1.creation_date.epochMillis < datetime($date).epochMillis + 100 * 24 * 60 * 60 * 1000
WITH tag, count(message1) AS countWindow1
// window 2
OPTIONAL MATCH (message2:comment)-[:comment_hastag_tag]->(tag)
  WHERE datetime($date).epochMillis + 100 * 24 * 60 * 60 * 1000 <= message2.creation_date.epochMillis
    AND message2.creation_date.epochMillis < datetime($date).epochMillis + 200 * 24 * 60 * 60 * 1000
WITH
  tag,
  countWindow1,
  count(message2) AS countWindow2
RETURN
  tag.name,
  countWindow1,
  countWindow2,
  CASE 
      WHEN countWindow1 >= countWindow2 THEN countWindow1 - countWindow2
      ELSE countWindow2 - countWindow1
  END AS diff
ORDER BY
  diff DESC,
  tag.name ASC
LIMIT 100