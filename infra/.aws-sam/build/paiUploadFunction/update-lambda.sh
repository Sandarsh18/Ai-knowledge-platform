#!/bin/bash
cd /home/sandarsh/projects/new/cc-internship/backend/upload
rm -f upload.zip
zip -r upload.zip .
aws lambda update-function-code --function-name pai-upload --zip-file fileb://upload.zip
echo "Lambda function updated successfully"
