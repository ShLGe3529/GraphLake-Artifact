// Parameters: $tagA, $dateA, $tagB, $dateB, $maxKnowsLimit

// Handle A
MATCH (person1:person)<-[:comment_hascreator_person]-(messageA:comment)-[:comment_hastag_tag]->(:tag {name: $tagA})
WHERE messageA.creation_date.year = datetime($dateA).year AND messageA.creation_date.month = datetime($dateA).month AND messageA.creation_date.day = datetime($dateA).day
OPTIONAL MATCH (person1)-[:person_knows_person]-(person2:person)<-[:comment_hascreator_person]-(messageA2:comment)-[:comment_hastag_tag]->(:tag {name: $tagA})
WHERE messageA2.creation_date.year = datetime($dateA).year AND messageA2.creation_date.month = datetime($dateA).month AND messageA2.creation_date.day = datetime($dateA).day
WITH person1, count(DISTINCT messageA) AS messageCountA, count(DISTINCT person2) AS friendsA

// Only keep persons who meet friend threshold for A
WHERE friendsA <= $maxKnowsLimit

// Handle B (repeat matching block, but careful with variable reuse)
MATCH (person1)<-[:comment_hascreator_person]-(messageB:comment)-[:comment_hastag_tag]->(:tag {name: $tagB})
WHERE messageB.creation_date.year = datetime($dateB).year AND messageB.creation_date.month = datetime($dateB).month AND messageB.creation_date.day = datetime($dateB).day
OPTIONAL MATCH (person1)-[:person_knows_person]-(person2B:person)<-[:comment_hascreator_person]-(messageB2:comment)-[:comment_hastag_tag]->(:tag {name: $tagB})
WHERE messageB2.creation_date.year = datetime($dateB).year AND messageB2.creation_date.month = datetime($dateB).month AND messageB2.creation_date.day = datetime($dateB).day
WITH person1, messageCountA, friendsA, count(DISTINCT messageB) AS messageCountB, count(DISTINCT person2B) AS friendsB

// Only keep persons who meet friend threshold for B
WHERE friendsB <= $maxKnowsLimit

RETURN
  person1.id,
  messageCountA,
  messageCountB
ORDER BY messageCountA + messageCountB DESC, person1.id ASC
LIMIT 20
