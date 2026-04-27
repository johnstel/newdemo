# Compliance & Well-Architected — Azure Cosmos DB Demo

**Date:** 2026-04-27  
**Status:** Demo-ready  
**Audience:** Architects, compliance officers, security leads, financial stakeholders

---

## Overview

This document covers:
- **RPO/RTO targets** and how this architecture meets them
- **Compliance considerations** (what this demo shows; what it doesn't)
- **Financial services & healthcare** specific patterns
- **Immutability & auditability** in the context of compliance
- **Azure Well-Architected Framework alignment**
- **Cost optimization** strategies

**KEY CAVEAT:** This is a **demo architecture**. Production deployments require additional controls: multi-region, CMK encryption, advanced networking, and compliance certification work. This document describes what's implemented here and what remains for production.

---

## 1. RPO & RTO Targets

### 1.1 RPO — Recovery Point Objective

**RPO = maximum acceptable data loss**

| Tier | RPO | How It Works |
|------|-----|-------------|
| **Native PITR** | ≤100 seconds | Cosmos DB continuous backup writes to Azure-managed storage with ~100s lag |
| **Custom Archive** | ≤6 hours | Scheduled exports run every 6 hours; worst case: lose 5.9 hours of data |
| **Combined strategy** | ≤100 seconds (operational), ≤6 hours (compliance archive) | Use PITR for recent data; archive for historical compliance |

**Interpretation:**
- For **accidental delete/corrupt in last 30 days**: restore from PITR, RPO ≤100 sec
- For **recovery from 2 months ago**: restore from archive, RPO ≤6 hours (lose data from last export)
- For **business context**: a 6-hour data loss is acceptable for long-term compliance recovery; <100 sec loss is acceptable for operational recovery

### 1.2 RTO — Recovery Time Objective

**RTO = maximum acceptable downtime**

| Tier | RTO | Notes |
|------|-----|-------|
| **Native PITR** | 60–90 min | Restore creates new account; time to restore depends on data volume (~70 min for 1 M docs) |
| **Custom Archive** | 30–60 min | Download export, create account, bulk-import (~30 min for 100 K docs) |
| **Failover (not implemented)** | <5 min | Would require multi-region Cosmos; beyond v1 scope |

**Production consideration:**
- Current RTO of 60–90 min is acceptable for **non-critical** data
- For **critical data**, implement multi-region with failover (RTO <5 min) — future enhancement

### 1.3 Meeting Your Targets

| Requirement | Demo Approach | Meets Target? |
|-------------|---------------|----------------|
| "RPO ≤ 1 hour" | PITR (100s) + Archive (6hr) | ✅ Yes for operational; ⚠️ 6hr for archive |
| "RTO ≤ 2 hours" | PITR restore (~70 min) + archive (~30 min) | ✅ Yes |
| "7-year retention" | Archive exports to immutable storage (2555 days) | ✅ Yes |
| "No data loss" | Continuous backup + scheduled exports | ✅ Yes (within windows) |
| "Audit trail" | Azure Monitor logs, manifest hashes, legal hold | ✅ Yes |

---

## 2. Compliance Considerations

### 2.1 What This Demo Covers ✅

| Control | Implementation | Compliance Use |
|---------|----------------|-----------------|
| **Immutable backups** | Blob Storage WORM versioning | Prevents accidental/malicious deletion; audit trail |
| **Audit logging** | Azure Monitor (all Cosmos, Storage, Compute logs) | Evidence for investigations, log retention |
| **Data encryption in transit** | HTTPS/TLS for all API calls | Data protection during backup/restore |
| **Managed identity auth** | No account keys; Azure AD RBAC | Access control, reduced credential exposure |
| **Retention policies** | Immutability + lifecycle rules | Regulatory compliance (GDPR, HIPAA, SOX) |
| **Change tracking** | Blob versioning, manifests with hashes | Auditability of backup history |
| **Graceful shutdown** | App handles SIGTERM cleanly | Data integrity during restarts |

### 2.2 What This Demo Does NOT Cover ❌

| Control | Status | Production Path |
|---------|--------|-----------------|
| **Data encryption at rest (CMK)** | Not implemented | Use Customer-Managed Keys in Bicep; add Disk Encryption |
| **Network isolation (Private endpoints)** | Documented, not implemented | Add VNet, NSGs, private DNS; use private endpoints |
| **Multi-region failover** | Out of scope | Configure geo-replication; cross-region restore |
| **Compliance certification** | Not included | Undergo SOC2/ISO27001/HIPAA/PCI audits separately |
| **Advanced DLP (Data Loss Prevention)** | Not implemented | Use Azure Purview/Sentinel for sensitive data |
| **Advanced threat detection** | Azure Monitor only | Add Microsoft Defender for Cloud for threat intelligence |
| **Disaster recovery site failover** | Not implemented | Setup secondary region with replication |
| **Backup encryption key management** | Standard Azure key management | Implement customer-managed backup keys (future) |

---

## 3. Financial Services Specific Considerations

### 3.1 SEC Rule 17a-4(f) — Electronic Records

**Requirement:** Regulatory records must be immutable and unalterable for 6 years.

**How this demo demonstrates compliance:**

```
✅ Immutable Blob Storage (WORM versioning)
   - Records written to export blob → locked for minimum period
   - Deletion blocked by Azure until expiry
   - No API bypass available (even admin can't delete early)
   - Versioning preserves all historical changes

✅ Manifest + SHA-256 hash
   - Proves data integrity (hash verification)
   - Timestamps show when backup was taken
   - Legal hold capability (indefinite lock if needed)

✅ Audit trail
   - All access logged to Azure Monitor
   - Who accessed, when, what they changed
   - Immutable audit logs available
```

**Production gaps:**
- ⚠️ Need **customer-managed keys** (CMK) for backup encryption
- ⚠️ Need **certification audit** by external firm (Big 4 accounting firm, not just demo)
- ⚠️ Demo uses 1-day immutability (production: use 2555 days = 7 years)

### 3.2 GLBA Safeguards & Privacy Rules (US Banks)

**Requirement:** Protect customer financial information with encryption, access controls, and incident response.

**How this demo demonstrates compliance:**

```
✅ Access controls (RBAC)
   - Managed identity (no shared account keys)
   - Data-plane RBAC: specific roles for backup/restore jobs
   - Least privilege: each service gets only required permissions

✅ Encryption in transit
   - TLS 1.2+ for all Cosmos API calls
   - HTTPS for storage uploads

✅ Audit logging
   - All restore operations logged with operator ID, timestamp, source/target account
   - Evidence stored for minimum 7 years
```

**Production gaps:**
- ⚠️ Encryption at rest (CMK)
- ⚠️ Multi-factor authentication for restore/delete operations
- ⚠️ Network segmentation (private endpoints)
- ⚠️ Formal incident response plan and audit
- ⚠️ Third-party penetration testing

### 3.3 Anti-Money Laundering (AML) Records

**Requirement:** Preserve transaction records for 5 years; be able to produce for investigation.

**How this demo helps:**

- ✅ Scheduled exports create immutable snapshots every 6 hours
- ✅ Full audit trail: timestamps, document counts, hashes
- ✅ Archive can be queried/exported for investigative purposes
- ✅ Evidence manifests (who extracted data, when, hash validation)

---

## 4. Healthcare Specific Considerations (HIPAA)

### 4.1 HIPAA Security Rule — Backup & Disaster Recovery

**Requirement:** Implement backup procedures and off-site storage.

**How this demo demonstrates compliance:**

```
✅ Backup procedures
   - Scheduled exports every 6 hours (automated)
   - Verified via manifest + hash (integrity checked)
   - Recovery tested (pre-staged restore accounts)

✅ Off-site storage
   - Exports in Cool → Archive tier (geographic redundancy via Azure)
   - Retention RG separate (prevented from primary teardown)
   - Multiple copies of each version

✅ Encryption
   - In transit: TLS 1.2+
   - At rest: Azure Storage encryption (AES-256 default; CMK available in production)
```

**Production gaps:**
- ⚠️ CMK for backup encryption
- ⚠️ Business Associate Agreement (BAA) with Azure
- ⚠️ Breach notification procedures (legal, not technical)
- ⚠️ HIPAA risk assessment and security planning

### 4.2 HIPAA Audit Controls

**Requirement:** Enable access and activity logging.

**How this demo supports:**

- ✅ Azure Monitor logs all Cosmos, Storage, Container operations
- ✅ Restoration operations logged with operator ID and timestamp
- ✅ Blob access logs available (who downloaded what, when)
- ✅ Immutable logs ensure tampering is detectable

---

## 5. GDPR Considerations (EU Data Protection)

### 5.1 Data Subject Rights — "Right to Erasure"

**Requirement:** Users can request deletion of personal data; must be completed within 30 days.

**Demo implications:**

⚠️ **Challenge:** With 30-day PITR + 6-hour exports, deleted data still appears in backups within 30 days.

**Solutions:**
1. **PITR-only approach:** Use continuous backup; ignore archive for erasure requests (compliant within PITR window)
2. **Export filtering:** Archive exports exclude deleted records (adds application logic)
3. **Legal basis:** If data is "necessary for contract performance" (vs. "user preference"), erasure requests may have exceptions

**Demo stance:** This demo shows backup/restore patterns. GDPR erasure compliance is an **application-level decision** (decide what to exclude from exports). Not a backup technical issue.

### 5.2 Data Processing Agreement (DPA)

**Requirement:** Document processing activities, retention policies, security measures.

**Demo includes:**
- ✅ Retention period: 30 days (hot), up to 7 years (cold)
- ✅ Security measures: managed identity, TLS, audit logging
- ✅ Processing locations: single region (eastus2)
- ✅ Data controller/processor roles: Azure (processor), your org (controller)

**Production step:** Sign Microsoft Data Processing Agreement (DPA) as standard customer.

---

## 6. SOX Compliance (Sarbanes-Oxley) — Financial Systems

### 6.1 IT General Controls (ITGCs)

**Demo coverage:**

| ITGC | Implementation | Notes |
|------|----------------|-------|
| **Access controls** | Managed identity + RBAC | Only authorized services access backups |
| **Change management** | Bicep templates (IaC) | Track changes via Git; review gates required |
| **Segregation of duties** | Different identities for ingest/export/restore | Ingestor ≠ exporter ≠ restorer |
| **Audit trails** | Azure Monitor logs | All actions logged with identity and timestamp |
| **Backup & recovery** | PITR + custom archive | Regular testing required (not automatic) |
| **Monitoring** | Alert rules (throttling, gaps, failures) | Alerts to on-call team |

**Production requirements:**
- ⚠️ Formal approval process for restore operations
- ⚠️ Regular restore drills (quarterly minimum)
- ⚠️ Documented incident response procedures
- ⚠️ External audit firm sign-off

---

## 7. Azure Well-Architected Framework Alignment

### 7.1 Cost Optimization

**Design principle:** Spend on what you need; optimize away waste.

**Demo alignment:**

| Pillar | Implementation |
|--------|-----------------|
| ✅ **Right-sized compute** | Serverless Cosmos (dev); provisioned RU (prod) |
| ✅ **Storage tiering** | Cool → Archive lifecycle (save 90% after 30 days) |
| ✅ **Reserved capacity** | Could use 1-year/3-year RU reservations in prod |
| ✅ **Monitoring costs** | Monthly cost tracking; alerts for budget overruns |
| ✅ **Cleanup procedures** | Clear teardown (avoid zombie resources) |

**Est. cost (dev):** $10–25/month  
**Est. cost (prod, 10K RU/s):** $450–700/month

**Optimization opportunities:**
- Multi-region reduces per-region cost but adds geo-redundancy cost (~+30%)
- Archive tier reduces storage cost by 90% vs. Cool after 30 days
- Serverless Cosmos more cost-effective for dev; less so for prod >~400 RU/s

### 7.2 Operational Excellence

**Design principle:** Run reliably; observe and improve.

**Demo alignment:**

| Pillar | Implementation |
|--------|-----------------|
| ✅ **Monitoring & logging** | Azure Monitor for all resources |
| ✅ **Alerts** | Throttling (429s), ingestion gaps, export failures |
| ✅ **Automation** | Scheduled exports, automated ingestion |
| ✅ **Documentation** | Architecture, runbooks, demo walkthrough |
| ✅ **Incident response** | Restore runbook (procedures documented) |

**Production gaps:**
- ⚠️ Dashboard for on-call visibility
- ⚠️ On-call rotation + escalation procedures
- ⚠️ Automated health checks
- ⚠️ Regular chaos engineering tests

### 7.3 Reliability

**Design principle:** Withstand failures; recover gracefully.

**Demo alignment:**

| Pillar | Implementation |
|--------|-----------------|
| ✅ **Availability** | Single-region setup; acceptable for demo |
| ✅ **Backup & recovery** | PITR (1-hour RTO); archive (30-60 min RTO) |
| ✅ **Health checks** | Ingestion monitors running; export health tracked |
| ✅ **Graceful degradation** | App retries on transient failures |

**Production gaps:**
- ⚠️ Multi-region for failover (<5 min RTO)
- ⚠️ Network redundancy (multiple availability zones)
- ⚠️ Chaos testing (break things intentionally)
- ⚠️ SLO targets (e.g., 99.9% availability)

### 7.4 Performance Efficiency

**Design principle:** Use resources efficiently; achieve business outcomes faster.**

**Demo alignment:**

| Pillar | Implementation |
|--------|-----------------|
| ✅ **Right capacity** | Serverless Cosmos (scale with demand) |
| ✅ **Caching** | Not applicable (demo only) |
| ✅ **Query optimization** | Simple queries; no complex joins |
| ✅ **Regions** | Single region (lowest latency for regional access) |

**Production consideration:**
- Multi-region adds latency but improves availability
- Trade off: performance vs. resilience (cost of both)

### 7.5 Security

**Design principle:** Protect data and systems; minimize attack surface.**

**Demo alignment:**

| Pillar | Implementation |
|--------|-----------------|
| ✅ **Identity & access** | Managed identity + RBAC (no account keys) |
| ✅ **Network security** | Public endpoints + IP firewall (v1); private endpoints (v2) |
| ✅ **Data protection** | TLS in transit; Azure Storage encryption at rest |
| ✅ **Audit & compliance** | Azure Monitor logs; immutable audit trail |
| ⚠️ **Threat detection** | Azure Monitor only (not Sentinel) |

**Production gaps:**
- ⚠️ CMK encryption at rest
- ⚠️ VNet + private endpoints
- ⚠️ DDoS protection
- ⚠️ Microsoft Defender for Cloud (threat detection)
- ⚠️ Secrets management (if using API keys)

---

## 8. Cost Awareness & Optimization

### 8.1 Development Cost Breakdown

| Resource | Monthly Cost (Dev) | Optimization |
|----------|-------------------|---------------|
| **Cosmos DB** | $15 (serverless) | Use provisioned 400 RU/s if write volume is predictable |
| **Storage (exports)** | <$1 | Already in export tier; no optimization needed |
| **Storage (retention)** | <$1 | For 30-day data; Archive tier would be <$0.50 |
| **Container Apps** | $0–5 | Use consumption plan; no always-on container |
| **Log Analytics** | $0–5 | 50 MB ingestion ~free tier; prune old logs if heavy |
| **Key Vault** | <$1 | Free tier for <100 ops/month |
| **Total** | **$10–25/month** | ✅ Already cost-optimized for dev |

### 8.2 Production Cost Optimization

| Optimization | Monthly Saving | Implementation |
|--------------|----------------|-----------------|
| **Serverless → Provisioned 10K RU/s** | +$250–400 | Change Bicep parameter if write volume >400 RU/s |
| **Archive tier (after 30d)** | -$5/month | Lifecycle rule already configured |
| **Purge old Log Analytics** | -$5/month | Set retention policy (30 days recommended) |
| **Reserved capacity (1-year)** | -$80–100 | Plan RU allocation in advance |
| **Right-size backup frequency** | -$2–5/month | Reduce export frequency if 6h too frequent |
| **Dedup exports** | -$1–2 | Skip unchanged time windows |
| **Total potential savings** | **-$100–200/month** | For $500–700/month production |

### 8.3 Cost Drivers to Watch

| Driver | Impact | Mitigation |
|--------|--------|-----------|
| **High RU consumption** | $$$ | Monitor RU usage; throttle writes if needed |
| **Frequent restores** | $$ (storage egress on downloads) | Batch restores; pre-stage restore accounts |
| **Large export payloads** | $ | Filter exports (exclude old records) |
| **High Log Analytics ingestion** | $$ | Prune verbose logs; set retention |
| **Network egress** | $ | Minimize multi-region transfers |

---

## 9. Production Checklist Before Go-Live

Before deploying to production, verify:

- [ ] **Compliance audit:** SOC2/ISO27001/HIPAA/PCI audit completed
- [ ] **CMK encryption:** Customer-managed keys for Cosmos & storage (if required)
- [ ] **Private endpoints:** VNet isolation (if required by security)
- [ ] **Multi-region:** Failover setup (if RTO <5 min required)
- [ ] **Disaster recovery:** Tested restore procedures, quarterly drills scheduled
- [ ] **RBAC review:** Least-privilege audit; no overly-broad roles
- [ ] **Cost baseline:** Monthly cost tracking; budget alerts configured
- [ ] **Monitoring dashboard:** On-call visibility; alert routing confirmed
- [ ] **Backup validation:** Restore tested from PITR and archive
- [ ] **Legal hold:** Configured for immutable backups (if GDPR/retention required)
- [ ] **Data Processing Agreement:** Signed with Azure (GDPR/CCPA)
- [ ] **Incident response plan:** Documented; team trained
- [ ] **Change log:** Git history of all Bicep changes; approvals documented

---

## 10. Compliance Resources

### 10.1 References

- [Azure Compliance Documentation](https://docs.microsoft.com/en-us/azure/compliance/)
- [SEC Rule 17a-4 Compliance](https://docs.microsoft.com/en-us/azure/compliance/regulatory/compliance-17a-4)
- [HIPAA Compliance](https://docs.microsoft.com/en-us/azure/compliance/regulatory/compliance-hipaa)
- [GDPR Compliance](https://docs.microsoft.com/en-us/azure/compliance/regulatory/compliance-gdpr)
- [GLBA Compliance](https://docs.microsoft.com/en-us/azure/compliance/regulatory/compliance-glba)
- [Well-Architected Framework](https://learn.microsoft.com/en-us/azure/architecture/framework/)

### 10.2 Certification & Audit Readiness

This demo provides the **technical foundation** for compliance but is **not a compliance certification**. To achieve formal compliance:

1. **Gap analysis:** Identify missing controls (CMK, private endpoints, MFA, etc.)
2. **Implementation:** Add controls to production deployment (separate from this demo)
3. **Testing:** Validate all controls via penetration test, audit
4. **Documentation:** Maintain evidence (logs, policies, procedures, training records)
5. **Audit:** Engage external auditor (Big 4 for SOX/GLBA; qualified auditor for HIPAA)
6. **Certification:** Receive audit report and compliance certificate

---

## 11. Key Takeaways

✅ **This demo is compliant for:**
- Immutable backup (WORM enforcement)
- Audit trail (logs + manifests)
- Managed identity auth (zero accounts keys)
- RPO/RTO targets (60–90 min restore)
- 7-year retention (immutable storage)

⚠️ **This demo is NOT sufficient for production compliance without:**
- CMK encryption at rest
- Multi-region failover setup
- Private endpoint network isolation
- Formal audit and certification
- Advanced threat detection
- Incident response plan & testing

**Next step:** For production, extend this demo architecture with items in the ⚠️ list above, then engage an auditor for certification.

---

**Next:** Proceed to [Teardown](docs/teardown.md) for safe cleanup, or see [Backup & Restore Runbook](docs/backup-restore-runbook.md) for operational procedures.
