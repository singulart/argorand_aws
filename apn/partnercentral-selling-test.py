import boto3
from datetime import datetime
import uuid
import secrets

client = boto3.client("partnercentral-selling", region_name="us-east-1")

def generate_estimator_url():
    return f"https://calculator.aws/#/estimate?id={secrets.token_hex(16)}"

def build_opportunity(index: int):
    return {
        "Catalog": "Sandbox",
        "PrimaryNeedsFromAws": ["Co-Sell - Deal Support"],
        "NationalSecurity": "No",
        "PartnerOpportunityIdentifier": f"Hubspot-{uuid.uuid4()}",
        "Customer": {
            "Account": {
                "Industry": "Financial Services",
                "OtherIndustry": "",
                "CompanyName": f"DemoBank Corp {index}",
                "WebsiteUrl": "https://demobank.example.com",
                "AwsAccountId": "123456789012",
                "Address": {
                    "City": "Washington",
                    "PostalCode": "20001",
                    "StateOrRegion": "Dist. of Columbia",
                    "CountryCode": "US",
                    "StreetAddress": "100 Constitution Ave"
                },
                "Duns": "123456789"
            },
            "Contacts": [
                {
                    "Email": f"contact{index}@demobank.example.com",
                    "FirstName": "John",
                    "LastName": "Doe",
                    "BusinessTitle": "CTO",
                    "Phone": "+12025550000"
                }
            ]
        },
        "Project": {
            "DeliveryModels": ["Professional Services"],
            "ExpectedCustomerSpend": [
                {
                    "Amount": "25000",
                    "CurrencyCode": "USD",
                    "Frequency": "Monthly",
                    "TargetCompany": f"DemoBank Corp {index}",
                    "EstimationUrl": generate_estimator_url()
                }
            ],
            "Title": f"Hybrid Cloud Migration Phased {index}",
            "ApnPrograms": ["Well-Architected"],
            "CustomerBusinessProblem": "The prospect requires modernization from on-premise legacy stack.",
            "CustomerUseCase": "Migration / Database Migration",
            "RelatedOpportunityIdentifier": 'O1234567'
            "SalesActivities": ["Customer has shown interest in solution"],
            "CompetitorName": "Microsoft Azure",
            "OtherSolutionDescription": "Full modernization with cloud-native architecture.",
            "AdditionalComments": "Strong executive sponsorship."
        },
        "OpportunityType": "Net New Business",
        "Marketing": {
            "CampaignName": "Q1 Financial Modernization",
            "Source": "Marketing Activity",
            "UseCases": ["Migration & Transfer"],
            "Channels": ["Email", "Virtual Event"],
            "AwsFundingUsed": "No"
        },
        "SoftwareRevenue": {
            "DeliveryModel": "Subscription",
            "Value": {"Amount": "12000", "CurrencyCode": "USD"},
            "EffectiveDate": "2025-01-01",
            "ExpirationDate": "2026-01-01"
        },
        "ClientToken": str(uuid.uuid4()),
        "LifeCycle": {
            "Stage": "Prospect",
            "NextSteps": "Architectural workshop scheduled.",
            "TargetCloseDate": "2025-12-31",
            "ReviewStatus": "Pending Submission",
            "NextStepsHistory": [
                {"Value": "Initial qualification complete", "Time": datetime.now()}
            ]
        },
        "Origin": "Partner Referral",
        "OpportunityTeam": [
            {
                "FirstName": "Lex",
                "LastName": "Buistov",
                "Email": "lex@argorand.io",
                "BusinessTitle": "OpportunityOwner",
                "Phone": "+12025551111"
            }
        ],
        "Tags": [
            {"Key": "Environment", "Value": "Test"},
            {"Key": "Priority", "Value": "High"}
        ]
    }

for i in range(1, 6):
    payload = build_opportunity(i)
    print(f"\n🎯 Creating Opportunity #{i} ...")

    create_resp = client.create_opportunity(**payload)
    opp_id = create_resp["Id"]   # ✅ Correct ID

    print(f"✅ Created: {opp_id}")

    print("📤 Submitting for visibility-only...")
    submit_resp = client.submit_opportunity(
        Catalog="Sandbox",
        Identifier=opp_id,
        InvolvementType="Co-Sell",   # ✅ Safe
        Visibility="Full"                     # ✅ Prevents unwanted co-sell escalation
    )

    print(f"✅ Submitted: {submit_resp}")
