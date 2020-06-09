# github-open-prs

A plugin for BitBar (https://getbitbar.com) to display the PRs you're mentioned on.

The current version is designed for use by developers that are part of one or more GitHub teams, in one or more organizations.

## Prerequisites

  - This tool is launched by [BitBar](https://getbitbar.com).
  - The launch shim script uses [rbenv](https://github.com/rbenv/rbenv).

## Installation

1. Install [BitBar](https://getbitbar.com); using [Homebrew](https://brew.sh/): `brew cask install bitbar`.

2. Install [rbenv](https://github.com/rbenv/rbenv); using Homebrew: `brew install rbenv`.

3. Clone this repo onto your Mac.

```sh
git clone https://github.com/devstuff/github-open-prs ~/Tools/github-open-prs
```

4. Copy the example configuration file into your home folder.

```sh
cp ./github-open-prs.yaml.example ~/.github-open-prs.yaml
```

5. Create a symlink to the `github-open-prs-exec` shim script in the BitBar plugins folder:

```sh
# Change the target path if you've moved the Plugins folder from the default location.
# The "30m" segment determines how often the script is run (30 minutes).
ln -s ~/Tools/github-open-prs/bin/github-open-prs-exec ~/.bitbar/Plugins/github-open-prs-exec.30m.sh
```

6. If you don't have one already, create a [Personal Access Token for your GitHub account](https://github.com/settings/tokens) so the script doesn't need your account password. Click **Generate New Token**, give it a name (e.g. *Command line tools*) and give it the following scopes (permissions):

    - `read:org`
    - `read:repo_hook`
    - `repo`
    - `user:email`

7. Edit the configuration file in your home folder:

    - Replace **YOUR_TOKEN_GOES_HERE** with the token value you just created.
    - Replace **YOUR_GITHUB_USER_NAME** with your GitHub user name.
    - Update the `teams` list to include the teams that you're part of, or who own repositories that you are interested in.
    - If required, change the `search_days` value. The default (30 days) works well for me.
    - Change the `api_host_url` only if you're connecting to a GitHub Enterprise server.

8. Right-click on the BitBar icon in the menu bar, click **Preferences** and then **Refresh All**. After a few seconds a new icon (🐙) will appear, along with the number of outstanding PRs.

   Each line on the popup menu will contain details of each PR:

    - Repository short name.
    - One or more status icons.
    - PR number.
    - PR title.
    - PR author.

The status icons are a combination of the PR's readiness status (*does it need a review?*), the workflow status (*have the required checks completed successfully?*) and mergeability status (*is it ready to be merged?*).

## Contributions

Constructive contributions are appreciated. Ruby is not my go-to language, so the script likely has style or best-practice issues 😁.
