# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- Initial repository structure
- MIT License
- README with architecture overview and quick start
- ROADMAP with phased platform delivery plan
- Design document for golden image pipeline and policy integration
- `build_cis_image.yml` — full Image Builder API integration: token exchange, blueprint creation, compose trigger, polling, AMI capture
- Skeleton playbooks: `deploy_and_scan.yml`, `generate_policy_data.yml`
- Sample inventory — Red Hat offline token read from `~/.ansible/ansible.cfg`, AWS credentials via env vars
- `.gitignore` covering credentials, collections, and generated output
- GitHub Actions lint workflow (ansible-lint, yamllint)
- Contributor Covenant Code of Conduct
