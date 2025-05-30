# DIY Mailchimp clone < 1000 lines of code

## Capabilities 

1. Sends bulk outreach emails using AWS SES
2. A/B testing
3. Content templates, personalization 
4. Natively trackable email open and CTA link click events
5. Simple campaign analytics (TODO)
6. 95% automated AWS infrastructure 
7. Massively parallelised email sending
8. CSV recipients list

## Prerequisites 

Your SES must be in [production mode](https://docs.aws.amazon.com/ses/latest/dg/request-production-access.html). 

Main domain identity set up manually, including DMARC settings. 

## Lambda functions

CI/CD stuff was out of scope for the sake of simplicity. Changing the Lambda code requires zipping up before `terraform apply`.

In `iac` folder: 

```sh
zip -r email_worker_lambda.zip ./email_worker_lambda

zip -r email_worker_lambda.zip ./email_worker_lambda

```

## Architecture 

TODO add picture


## Caveats 

After creating Route53 hosted zone for the analytics subdomain, I had to manually create NS record on the DNS provider side. 
