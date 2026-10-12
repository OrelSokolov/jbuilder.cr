json.extract! post, :id, :body
json.author do
  parts = post.author_name.split(" ", 2)
  json.first_name parts[0]
  json.last_name parts.size > 1 ? parts[1] : ""
end
