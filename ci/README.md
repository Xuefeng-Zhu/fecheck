# CI workflow

`github-actions-ci.yml` is the GitHub Actions workflow for this repo (Fe
v26.6.0 install, `fe fmt --check`, `scripts/test.sh`, demo). It lives here
because the token used for the first push lacked the `workflow` scope. To
enable it, move it into place:

    mkdir -p .github/workflows && git mv ci/github-actions-ci.yml .github/workflows/ci.yml
