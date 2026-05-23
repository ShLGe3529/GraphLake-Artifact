// Q5. Most active Posters of a given Topic
/*
:params { tag: 'Rumi' }
*/
MATCH (tag:tag {name: $tag})-[:comment_hastag_tag_reverse]->(message:comment)-[:comment_hascreator_person]->(person:person)
OPTIONAL MATCH (message)-[likes:person_likes_comment_reverse]->(:person)
WITH person, message, count(likes) AS likeCount
OPTIONAL MATCH (message)-[:comment_replyof_comment_reverse]->(reply:comment)
WITH person, message, likeCount, count(reply) AS replyCount
WITH person, count(message) AS messageCount, sum(likeCount) AS likeCount, sum(replyCount) AS replyCount
RETURN
  person.id,
  replyCount,
  likeCount,
  messageCount,
  1*messageCount + 2*replyCount + 10*likeCount AS score
ORDER BY
  score DESC,
  person.id ASC
LIMIT 100
