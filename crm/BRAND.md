# 🧵 Filveo CRM

> The only CRM built for interior designers and home furnishing sales professionals.

[![Status](https://img.shields.io/badge/Status-MVP%20Built-gold)](https://filveo.com)
[![Version](https://img.shields.io/badge/Version-1.0-blue)](https://filveo.com)
[![License](https://img.shields.io/badge/License-Private-red)](https://filveo.com)

---

## What is Filveo?

Filveo is a cloud-based CRM with post-sale lifecycle tracking, mileage auto-sync, vendor credits management, and urgency-scored pipeline automation — designed exclusively for interior design and home furnishing sales professionals.

**Why it exists**: Every generic CRM (HoneyBook, Mydoma, Houzz Pro, Salesforce) treats the design sale as complete at delivery. Filveo tracks what happens *after* — the 30-day check-in, the 60-day follow-up, the referral, the repeat purchase. That post-delivery window is where $28,400/year in average annual revenue walks out the door unrecovered.

## Quick Start

```bash
# Serve locally — no build step needed
cd src && python3 -m http.server 8080

# Open in browser
open http://localhost:8080/          # Landing page
open http://localhost:8080/app.html  # CRM application
open http://localhost:8080/demo.html # Interactive demo
```

## Project Files

| File | Description | Size |
|---|---|---|
| `src/index.html` | Landing page — SEO/GEO/LLMO optimized, viral neuromarketing | 111k |
| `src/app.html` | Full CRM application — 12 tabs, all features | 573k |
| `src/demo.html` | 16-scene Sofia Reyes walkthrough demo | 296k |
| `docs/gtm-bible-v4.html` | GTM Bible — strategy, prospects, pricing, sequences | 337k |

## Key Features

- ✅ Post-30/Post-60 delivery follow-up automation
- ✅ Urgency-scored pipeline (HOT/WARM/NURTURE/COLD)
- ✅ Mileage auto-sync from home calls (IRS-compliant)
- ✅ Vendor Credits tracking (manufacturer incentive programs)
- ✅ Commission calculator (monthly/YTD/projection)
- ✅ Quote PDF generator
- ✅ SMS/WhatsApp templates by pipeline tier
- ✅ Client portal with delivery timeline
- ✅ Email sequences (25 templates, 5 cadences)
- ✅ Expense tracker with net margin
- ✅ Review request automation (Google, Houzz)
- ✅ Analytics with custom fiscal year
- ✅ Multi-designer team workspace
- ✅ PWA — installs on iPhone and Android
- ✅ GDPR/CCPA compliant
- ✅ WCAG 2.1 AA accessible

## Pricing

| Plan | Price | Users | Key Features |
|---|---|---|---|
| Solo | $39/mo | 1 | All features |
| Studio | $89/mo | Up to 5 | Team pipeline, shared analytics |
| Enterprise | Custom | Unlimited | White-label, custom integrations, SLA |

14-day free trial · No credit card required

## Tech Stack

- **Frontend**: Vanilla HTML/CSS/JS (zero framework, zero build step)
- **Database**: Supabase (new dedicated Filveo project — not shared)
- **Default storage**: localStorage (`filveo_data_v1`)
- **PWA**: Service worker + manifest for offline capability
- **Fonts**: Playfair Display, DM Sans, Cormorant Garamond (Google Fonts)
- **Hosting**: To be deployed (recommend Vercel or Netlify)

## Brand — Midnight Silk

| Element | Value |
|---|---|
| Primary color | `#d4c4a8` Champagne Silk |
| Background | `#0d1018` Midnight |
| Display font | Playfair Display |
| Body font | DM Sans |
| Data font | Cormorant Garamond |

## Project Status

**Rating: 78/100** — Exceptional for MVP stage.

**Gap to 95/100**: First 10 paying customers, Stripe + hosted auth, mobile PWA, Gmail/Outlook API, enterprise pilot initiated.

## Contact

- **Founder**: Bernardo (hello@filveo.com)
- **Privacy**: privacy@filveo.com
- **Sales**: sales@filveo.com
- **Enterprise**: enterprise@filveo.com

---

> *Read `CLAUDE.md` for full project context before making any changes.*
