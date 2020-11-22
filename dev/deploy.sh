hugo --gc --minify --enableGitInfo
aws --profile energysense-dev-deploy --region eu-west-1 s3 rm s3://dev.l1x.be/ --recursive
aws --profile energysense-dev-deploy --region eu-central-1 s3 sync public/ s3://dev.l1x.be/ --acl public-read
aws --profile energysense-dev-deploy cloudfront create-invalidation --distribution-id E3RDRLBPA4EVPP --paths  "/*"
