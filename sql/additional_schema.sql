# Change Columns of posts table
# DELETE: mime, imgdata
# ADD: account_name varchar(64)
# account_name from users.account_name

CREATE TABLE good_posts LIKE posts;
ALTER TABLE good_posts DROP COLUMN mime;
ALTER TABLE good_posts DROP COLUMN imgdata;
ALTER TABLE good_posts ADD COLUMN account_name varchar(64);
REPLACE INTO good_posts SELECT p.id, p.user_id, p.body, p.created_at, u.account_name from posts p JOIN users u ON p.user_id = u.id;
RENAME TABLE posts TO posts_old, good_posts TO posts;

#############################

# Change Columns of comments table
# ADD: account_name varchar(64)
# account_name from users.account_name

CREATE TABLE good_comments LIKE comments;
ALTER TABLE good_comments ADD COLUMN account_name varchar(64);
REPLACE INTO good_comments SELECT c.id, c.post_id, c.user_id, c.comment, c.created_at, u.account_name
FROM comments c
JOIN users u ON c.user_id = u.id;
RENAME TABLE comments TO comments_old, good_comments TO comments;

#############################
ALTER TABLE comments ADD INDEX post_id(post_id);

