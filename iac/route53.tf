resource "aws_route53_zone" "analytics" {
  name = aws_ses_domain_identity.analytics.domain
}

output "ns_records_to_add_in_lightsail" {
  value = aws_route53_zone.analytics.name_servers
  description = "Add these as NS records for analytics.argorand.io in your Lightsail DNS zone"
}