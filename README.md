# ghrep
Search (&amp; replace) globally across multiple GitHub repos, with full regex parsing.

# Installation Steps

In order to use ghrep, you'll need to setup a few environment variables:

GITHUB_USER - set this to your GitHub username (defaults to your current username)
GITHUB_TOKEN - set this to a GitHub API token that corresponds with your username
GITHUB_ORG - if using an org, set this to the org name
GHREP_DIR - set this to a destination/working directory for the repos that ghrep works with

Your ssh config should be setup for key based logins to `git@github.org`. If you use a different Host entry in your ssh config for this purpose, set the GITHUB_HOST to that.
