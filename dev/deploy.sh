hugo --gc --minify --enableGitInfo --buildFuture
aws --profile li-istvan --region eu-west-1 s3 rm s3://dev.l1x.be/ --recursive
aws --profile li-istvan --region eu-central-1 s3 sync public/ s3://dev.l1x.be/ --acl public-read
aws --profile li-istvan cloudfront create-invalidation --distribution-id E3RDRLBPA4EVPP --paths  "/*"
