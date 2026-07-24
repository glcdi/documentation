#!/usr/bin/env python3
"""Define every AUTHENTICATION diagram once. Emit a JSON {key → plantuml-server URL}
that the HTML presentation embeds; the same PlantUML sources are also pasted
verbatim into AUTHENTICATION.md as ```plantuml fences.

After editing a diagram, run this script and copy the matching URL into the
corresponding <img src="..."> in AUTHENTICATION.html, then sync the PlantUML
source into AUTHENTICATION.md.
"""

import json, sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

_here = Path(__file__).resolve().parent
pe = SourceFileLoader("plantuml_encode", str(_here / "plantuml-encode.py")).load_module()

DIAGRAMS = {}

# ============================================================
# OVERVIEW: phase timeline
# ============================================================
DIAGRAMS["overview-timeline"] = r"""
@startuml
!theme plain
skinparam defaultFontSize 12
skinparam roundcorner 8

rectangle "**Phase 1 - Today**\nAuthority KC + onboarding\nConnector-only DSP trust\nX-Api-Key at the UI" as P1 #E8F5E9
rectangle "**Phase 2 - Next**\nUser OIDC against\nAuthority KC\noauth2-proxy at the UI" as P2 #FFF9C4
rectangle "**Phase 3 - Later**\nPer-participant Keycloaks\nfederated to Authority\nTwo-tier UI login" as P3 #FFE0B2
rectangle "**Phase 4 - Long-term**\nOID4VCI / OID4VP\nVerifiable Credentials\nDecentralised trust" as P4 #E1BEE7

P1 -right-> P2 : add user OIDC
P2 -right-> P3 : federate user mgmt
P3 -right-> P4 : swap KC → VC/VP

note bottom of P1 : Shipped Phase 1.6\n(djangoldp-glcdi 3.1.3 +\nrealm-admin SA)
note bottom of P4 : Aligns with EUDI Wallet /\nGaia-X Tier 3
@enduml
"""

# ============================================================
# PHASE 1 - ARCHITECTURE (current)
# ============================================================
DIAGRAMS["p1-architecture"] = r"""
@startuml
!theme plain
skinparam defaultFontSize 11
skinparam roundcorner 6
skinparam componentStyle rectangle
left to right direction

cloud "Authority VM\nauthority.glcdi.startinblox.com" as AUTH #E3F2FD {
  component "Authority Keycloak\nrealm: glcdi" as KC {
    component "Clients:\n• governance (SA: realm-admin)\n• glcdi-connector-<org> × N" as KCC
    component "Realm roles:\nglcdi_producer\n..." as KCR
    component "User attribute:\nglcdi_organization" as KCA
  }
  component "Onboarding backend\n(djangoldp-glcdi)" as OB
}

cloud "Participant VM (× N)\ne.g. caney-fork.glcdi.startinblox.com" as PV #E8F5E9 {
  component "Catalog UI (Hubl)" as UI
  component "EDC Controlplane\n+ Dataplane" as EDC
}

AUTH -[hidden]right- PV

OB ..> KC : Admin API\n(realm-admin SA)
EDC ..> KC : client_credentials\n(glcdi-connector-<org>)
UI --> EDC : /management/\n(X-Api-Key only)
EDC <--> EDC : DSP\n(Bearer JWT, glcdi_* claims)
@enduml
"""

# ============================================================
# PHASE 1 - SEQUENCE: ONBOARDING
# ============================================================
DIAGRAMS["p1-seq-onboarding"] = r"""
@startuml
!theme plain
skinparam defaultFontSize 11

actor "Organisation\noperator" as OP
participant "Onboarding form\n/registration/" as FORM
participant "djangoldp-glcdi" as DG
participant "SMTP" as MAIL
actor "Dataspace\nAuthority admin" as ADM
participant "Admin dashboard\n/registration/admin/" as DASH
participant "Authority KC\nAdmin API" as KCAPI

OP -> FORM : Fill org details +\nupload logo
FORM -> DG : POST RegisterParticipant
DG -> DG : status = "pending"
DG -> MAIL : Notification email\n→ GLCDI_ADMIN_MAILS
MAIL --> ADM : "New registration"
ADM -> DASH : Review submission
ADM -> DASH : Approve\n(picks org type +\nrole assignments)
DASH -> KCAPI : POST /groups\n(org group)
DASH -> KCAPI : POST /users\n(set glcdi_organization\nattribute)
DASH -> KCAPI : Role mapping:\nglcdi_member +\ntype role
KCAPI --> DASH : user id
DASH -> MAIL : Invite email\n(set-password link)
MAIL --> OP : Welcome - set password
note over DG, KCAPI
  Phase 1 today: Authority KC is the
  **only** user directory in the dataspace.
end note
@enduml
"""

# ============================================================
# PHASE 1 - SEQUENCE: CONNECTOR TRUST
# ============================================================
DIAGRAMS["p1-seq-connector"] = r"""
@startuml
!theme plain
skinparam defaultFontSize 11

participant "Consumer\nconnector\n(Point Blue)" as CC
participant "Authority KC" as KC
participant "Provider\nconnector\n(Caney Fork)" as PC

== Token acquisition ==
CC -> KC : POST /token\nclient_credentials\n(glcdi-connector-point-blue)
KC -> KC : Look up SA user\n→ resolve glcdi_* claims
KC --> CC : JWT (signed by KC,\nglcdi_membership,\nglcdi_roles, ...)

== DSP exchange ==
CC -> PC : DSP catalog request\nAuthorization: Bearer <JWT>
PC -> KC : GET /certs (JWKS)
KC --> PC : public keys
PC -> PC : Verify signature\nExtract glcdi_* claims\ninto ClaimToken
PC -> PC : Policy evaluation\n(members-only,\nregenerative-producers,\n...)
PC --> CC : Catalog (filtered by\npolicy outcome)

note over CC, PC
  Connector identity is **not** end-user identity.
  Each connector is itself a service account on Authority KC.
end note
@enduml
"""

# ============================================================
# PHASE 2 - ARCHITECTURE (governance user OIDC)
# ============================================================
DIAGRAMS["p2-architecture"] = r"""
@startuml
!theme plain
skinparam defaultFontSize 11
skinparam componentStyle rectangle
left to right direction

cloud "Authority VM" as AUTH #E3F2FD {
  component "Authority Keycloak\nrealm: glcdi\n--\n+ glcdi-ui (user OIDC client)\n+ per-org groups\n+ human users with\n   glcdi_organization" as KC
  component "Onboarding backend\n(Phase 1.6 unchanged)" as OB
}

cloud "Participant VM (× N)" as PV #E8F5E9 {
  component "Catalog UI\n(now OIDC)" as UI
  component "oauth2-proxy\n(validates JWT)" as OP2
  component "EDC connector" as EDC
}

AUTH -[hidden]right- PV

UI ..> KC : OIDC code flow\n(glcdi-ui client)
UI --> OP2 : /management/\nBearer + X-Api-Key
OP2 --> EDC : validated requests
OP2 ..> KC : verify token\n(JWKS)
EDC <--> EDC : DSP
EDC ..> KC : client_credentials
@enduml
"""

# ============================================================
# PHASE 2 - SEQUENCE: USER LOGIN
# ============================================================
DIAGRAMS["p2-seq-login"] = r"""
@startuml
!theme plain
skinparam defaultFontSize 11

actor "User\n(Caney Fork)" as U
participant "Catalog UI\n(Hubl)" as UI
participant "Authority KC\nrealm: glcdi" as KC
participant "oauth2-proxy\n(at participant edge)" as OP
participant "EDC Management API" as EDC

U -> UI : Visit\nhttps://caney-fork…/catalogue/
UI -> KC : OIDC redirect\n(client: glcdi-ui)
U -> KC : Login\n(user lives in Authority KC)
KC --> UI : Authorization code
UI -> KC : Exchange code → tokens
KC --> UI : ID + access token\n(glcdi_organization=caney-fork,\nglcdi_roles=[member, producer])
UI -> UI : Render with org-scoped\nrole-aware UI
U -> UI : Click "Browse catalog"
UI -> OP : GET /management/v3/catalog/request\nAuthorization: Bearer <jwt>\nX-Api-Key: …
OP -> KC : Verify JWT (JWKS)
KC --> OP : valid + claims
OP -> EDC : Forward request
EDC --> OP : catalog
OP --> UI : catalog
UI --> U : Render

note over U, EDC
  **One IdP, one login.** All users live on the Authority KC.
  Participants no longer run their own KC for users.
end note
@enduml
"""

# ============================================================
# PHASE 3 - ARCHITECTURE (local KCs federated)
# ============================================================
DIAGRAMS["p3-architecture"] = r"""
@startuml
!theme plain
skinparam defaultFontSize 11
skinparam componentStyle rectangle

cloud "Authority VM" as AUTH #E3F2FD {
  component "Authority Keycloak\nrealm: glcdi" as KC {
    component "IdP brokering\n(one IdP per participant)" as KCB
    component "Federated users\n+ governance roles\n+ glcdi_organization" as KCU
  }
  component "Onboarding backend\n(provisions IdP entries\non approval)" as OB
}

cloud "Caney Fork VM" as PV1 #E8F5E9 {
  component "Local KC\nrealm: caney-fork" as PKC1
  component "Catalog UI" as UI1
  component "oauth2-proxy" as OP1
  component "EDC connector" as EDC1
}

cloud "Point Blue VM" as PV2 #FFF3E0 {
  component "Local KC\nrealm: point-blue" as PKC2
  component "Catalog UI" as UI2
  component "oauth2-proxy" as OP2
  component "EDC connector" as EDC2
}

KCB ..> PKC1 : OIDC brokering\n(KC_IDP_HINT=caney-fork)
KCB ..> PKC2 : OIDC brokering\n(KC_IDP_HINT=point-blue)

OB ..> KC : create IdP entry\nfor new participant
OB ..> PKC1 : create participant admin\n(via Admin API)

UI1 ..> KC : OIDC (catalog-ui-governance)
UI1 ..> PKC1 : silent OIDC\n(catalog-ui, iframe)
UI1 --> OP1
OP1 --> EDC1

UI2 ..> KC : OIDC
UI2 ..> PKC2 : silent OIDC
UI2 --> OP2
OP2 --> EDC2

EDC1 <--> EDC2 : DSP

note bottom of PV1
  Participant ops own day-to-day
  user management (HR, role changes,
  password resets) on their local KC.
end note
@enduml
"""

# ============================================================
# PHASE 3 - SEQUENCE: TWO-TIER LOGIN
# ============================================================
DIAGRAMS["p3-seq-login"] = r"""
@startuml
!theme plain
skinparam defaultFontSize 11

actor "User\n(Caney Fork)" as U
participant "Catalog UI\n(Hubl)" as UI
participant "Authority KC\nrealm: glcdi" as AKC
participant "Local KC\nrealm: caney-fork" as PKC
participant "oauth2-proxy\n(participant edge)" as OP
participant "EDC Mgmt API" as EDC

== Tier 1: governance login ==
U -> UI : Visit catalogue/
UI -> AKC : OIDC\n(catalog-ui-governance,\nKC_IDP_HINT=caney-fork)
AKC -> PKC : IdP brokering redirect
U -> PKC : Login at **local KC**
PKC --> AKC : Token (federated)
AKC --> UI : Governance JWT\n(glcdi_organization,\ngovernance roles)

== Tier 2: silent participant token ==
UI -> PKC : Silent OIDC\n(catalog-ui client,\n/silent-callback.html iframe)
PKC --> UI : Local JWT\n(participant-scoped roles)

== Calling EDC ==
UI -> OP : /management/…\nAuthorization: Bearer <local JWT>\nX-Api-Key: …
OP -> PKC : Verify (local JWKS)
PKC --> OP : OK
OP -> EDC : Forward
EDC --> OP : Response
OP --> UI : Response

note over U, EDC
  Two-tier flow lets governance audit "who acted on behalf of caney-fork"
  while participant ops keep authority over their own user directory.
end note
@enduml
"""

# ============================================================
# PHASE 4 - ARCHITECTURE (OID4VC/VP)
# ============================================================
DIAGRAMS["p4-architecture"] = r"""
@startuml
!theme plain
skinparam defaultFontSize 11
skinparam componentStyle rectangle

cloud "Authority VM" as AUTH #E3F2FD {
  component "VC Issuer\n(OID4VCI)\ne.g. Walt.id / KC plugin" as ISS
  component "Trust list\n(issuer DIDs)" as TL
  component "Onboarding backend\n(triggers VC issuance\non approval)" as OB
}

cloud "User device" as UD #F3E5F5 {
  component "EUDI Wallet\nor compatible holder" as WAL
}

cloud "Caney Fork VM" as PV1 #E8F5E9 {
  component "Catalog UI\n(OID4VP verifier)" as UI1
  component "EDC connector\n+ iam-identity-trust" as EDC1
  component "Identity Hub\n(holds VCs for connector)" as IH1
}

cloud "Point Blue VM" as PV2 #FFF3E0 {
  component "Catalog UI" as UI2
  component "EDC connector" as EDC2
  component "Identity Hub" as IH2
}

ISS ..> WAL : Issue user VC\n(OID4VCI)\nMembershipCredential,\nRoleCredential
ISS ..> IH1 : Issue connector VC
ISS ..> IH2 : Issue connector VC

WAL ..> UI1 : Present VP\n(OID4VP / QR code)
UI1 ..> TL : Resolve issuer DID\nverify trust
EDC1 <--> EDC2 : DSP via DCP\n(connectors exchange VPs)

note bottom of TL
  No JWKS / Authority KC in the trust path.
  Verifiers check signatures + trust list.
  Aligns with Gaia-X Trust Framework / EUDI ARF.
end note
@enduml
"""

# ============================================================
# PHASE 4 - SEQUENCE: VC ISSUANCE (OID4VCI)
# ============================================================
DIAGRAMS["p4-seq-vci"] = r"""
@startuml
!theme plain
skinparam defaultFontSize 11

actor "Approved user" as U
participant "Wallet" as W
participant "Onboarding\nbackend" as OB
participant "VC Issuer\n(OID4VCI)" as ISS
participant "Authority\nadmin" as ADM

U -> OB : Submitted registration\n(Phase 1.6 flow, but now\nincludes user DID)
ADM -> OB : Approve
OB -> ISS : Authorize issuance\n(membership + role VC)
ISS --> OB : Credential offer\n(QR / deep link)
OB --> U : "Scan this with your wallet"
U -> W : Scan offer
W -> ISS : Token request\n(pre-authorized_code)
ISS --> W : Access token
W -> ISS : POST /credential
ISS -> ISS : Sign VC with\nissuer DID's key
ISS --> W : VC (W3C VC,\nSD-JWT-VC or JWT-VC)
W -> W : Store credential\nin wallet

note over U, W
  User credentials are **not** in any IdP anymore.
  They live in the wallet, under the user's control.
end note
@enduml
"""

# ============================================================
# PHASE 4 - SEQUENCE: VP PRESENTATION (OID4VP)
# ============================================================
DIAGRAMS["p4-seq-vp"] = r"""
@startuml
!theme plain
skinparam defaultFontSize 11

actor "User" as U
participant "Wallet" as W
participant "Catalog UI\n(OID4VP verifier)" as UI
participant "Trust list" as TL
participant "EDC Mgmt API" as EDC

U -> UI : Visit catalogue/
UI -> UI : Build VP request\n(needs MembershipCredential\n+ RoleCredential)
UI --> U : Show QR / cross-device flow
U -> W : Scan
W -> W : Select matching VCs\n(user consents)
W -> UI : POST presentation_submission\n(signed VP)
UI -> UI : Verify VP signature
UI -> TL : Resolve issuer DID
TL --> UI : Issuer DID document\n(+ trust framework status)
UI -> UI : Extract glcdi_* claims\nfrom VC contents
UI --> U : Session established\n(short-lived JWT for UI)

U -> UI : Click "Browse catalog"
UI -> EDC : /management/…\nAuthorization: Bearer <session JWT>\nX-Api-Key: …
EDC --> UI : Catalog
UI --> U : Render

note over U, EDC
  Same /management/ edge as P2/P3 - defence in depth preserved.
  What changes is **how the user proves who they are**: VP, not OIDC.
end note
@enduml
"""

# ============================================================
# emit
# ============================================================
out = {key: pe.url(src) for key, src in DIAGRAMS.items()}
print(json.dumps(out, indent=2))
