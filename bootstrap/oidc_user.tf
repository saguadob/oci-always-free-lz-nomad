data "oci_identity_domains" "current" {
  #Required
  compartment_id = var.tenancy_ocid
}

resource "oci_identity_domains_user" "github" {
  idcs_endpoint = data.oci_identity_domains.current.domains.0.home_region_url
  schemas = [
    "urn:ietf:params:scim:schemas:core:2.0:User",
    "urn:ietf:params:scim:schemas:oracle:idcs:extension:userState:User",
    "urn:ietf:params:scim:schemas:oracle:idcs:extension:OCITags",
    "urn:ietf:params:scim:schemas:oracle:idcs:extension:capabilities:User",
    "urn:ietf:params:scim:schemas:oracle:idcs:extension:user:User"
  ]
  user_name   = "github-oidc"
  description = "Automation account used by Github Runners."
  active      = true

  urnietfparamsscimschemasoracleidcsextensionuser_user {
    service_user = true
  }
}

# 2. Reference or create the administrator group
data "oci_identity_groups" "administrators" {
  compartment_id = var.tenancy_ocid
  name           = "Administrators" # Default OCI admin group name, or your custom admin group
}

# 3. Add the user to the administrator group
resource "oci_identity_user_group_membership" "admin_membership" {
  user_id  = oci_identity_domains_user.github.ocid
  group_id = data.oci_identity_groups.administrators.groups[0].id
}

resource "oci_identity_domains_app" "github" {
  idcs_endpoint = data.oci_identity_domains.current.domains.0.home_region_url
  schemas = [
    "urn:ietf:params:scim:schemas:oracle:idcs:App",
    "urn:ietf:params:scim:schemas:oracle:idcs:extension:OCITags"
  ]
  display_name = "github-token-exchange"
  description  = "OAuth client for GitHub OIDC token exchange; no administrative roles"
  active       = true

  based_on_template {
    value = "CustomWebAppTemplateId"
  }

  is_oauth_client = true
  client_type     = "confidential"
  allowed_grants  = ["client_credentials"]
  is_login_target = false
  show_in_my_apps = false
  # Do not grant Identity Domain Administrator or other admin roles to this app.
}

resource "oci_identity_domains_identity_propagation_trust" "github" {
  idcs_endpoint = data.oci_identity_domains.current.domains.0.home_region_url
  schemas       = ["urn:ietf:params:scim:schemas:oracle:idcs:IdentityPropagationTrust"]
  name          = "github"
  type          = "JWT"
  active        = true

  issuer                    = "https://token.actions.githubusercontent.com"
  public_key_endpoint       = "https://token.actions.githubusercontent.com/.well-known/jwks"
  oauth_clients             = [oci_identity_domains_app.github.name]
  allow_impersonation       = true
  subject_claim_name        = "sub"
  subject_mapping_attribute = "userName"
  subject_type              = "User"
  # Impersonation mappings are returned=request; include them in refresh reads.
  attribute_sets = ["all"]

  impersonation_service_users {
    rule  = "sub eq 'repo:${var.repo}:ref:refs/heads/${var.branch}'"
    value = oci_identity_domains_user.github.id
    ocid  = oci_identity_domains_user.github.ocid
  }
}

output "oidc_client_identifier" {
  value = oci_identity_domains_app.github.name
}

output "oidc_client_secret" {
  value = oci_identity_domains_app.github.client_secret
}

output "oci_identity_domain_base_url" {
  value = data.oci_identity_domains.current.domains.0.home_region_url
}