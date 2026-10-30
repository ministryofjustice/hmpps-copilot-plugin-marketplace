#!/usr/bin/env bash
#
# migrate-ghcr-to-ecr.sh
#
# Migrates an HMPPS repository's GitHub Actions build, push, deploy and Snyk
# workflows from GHCR (ghcr.io) to AWS ECR. This is the non-Copilot version of
# the hmpps-repository-tools:migrate-ghcr-to-ecr skill.
#
# Requirements: git, gh (authenticated), perl (bundled with macOS and Linux).
#
# Run it from the root of a clone of the repository:
#
#   ./migrate-ghcr-to-ecr.sh            # make the changes, show the diff, ask before commit/push/PR
#   ./migrate-ghcr-to-ecr.sh --help
#
# It never commits, pushes or opens a pull request without asking (or --yes).

set -euo pipefail

BRANCH="feat/migrate_build_deploy_to_ECR"
ASSUME_YES=false
SKIP_PREFLIGHT=false
HELM_SET_PATH=""

REQUIRED_VARS="CLOUD_PLATFORM_ECR_REGISTRY_URL ECR_REGION ECR_REPOSITORY"
REQUIRED_SECRET="ECR_ROLE_TO_ASSUME"

if [ -t 1 ]; then
  BOLD=$'\e[1m'; RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; RESET=$'\e[0m'
else
  BOLD=""; RED=""; GREEN=""; YELLOW=""; RESET=""
fi
info() { printf '%s\n' "${BOLD}==>${RESET} $*"; }
ok()   { printf '%s\n' "  ${GREEN}✔${RESET} $*"; }
warn() { printf '%s\n' "  ${YELLOW}!${RESET} $*"; }
fail() { printf '%s\n' "  ${RED}✘${RESET} $*"; }
die()  { printf '%s\n' "${RED}Error:${RESET} $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Run from the root of a clone of the repository to migrate.

Options:
  --branch NAME       Branch to create (default: $BRANCH)
  --helm-path PATH    Helm --set path for the image repository, for example
                      'image.repository'. Default: the path of the single
                      image.repository key in helm_deploy/**/values*.yaml
                      (for example 'image.repository' or
                      'generic-service.image.repository').
  --skip-preflight    Don't check the repository-level ECR variables and secret
                      (use only if they are set at organisation level).
  -y, --yes           Commit, push and open a pull request without asking.
  -h, --help          Show this help.

What it does:
  1. Checks gh, authentication and the ECR variables and secret.
  2. Creates $BRANCH from the latest default branch.
  3. Switches the shared workflows:
       docker_build.yml                -> docker_build_ecr.yml
       docker_push.yml                 -> docker_push_ecr.yml
       deploy_env.yml                  -> deploy_to_env.yml
       security_snyk_scan[_private].yml -> security_snyk_scan_ecr.yml
     adding the ECR inputs, the ECR_ROLE_TO_ASSUME secret, id-token: write and
     the Helm image repository override. Commented-out jobs are updated too.
  4. Replaces the ghcr.io image repository in helm_deploy/*/values*.yaml.
  5. Shows the diff and anything that needs a manual check, then asks before
     committing, pushing and opening a pull request.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --branch) BRANCH="${2:?--branch needs a value}"; shift 2 ;;
    --helm-path) HELM_SET_PATH="${2:?--helm-path needs a value}"; shift 2 ;;
    --skip-preflight) SKIP_PREFLIGHT=true; shift ;;
    -y|--yes) ASSUME_YES=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown option: $1" ;;
  esac
done

confirm() {
  # confirm "question" -> 0 if yes
  if $ASSUME_YES; then return 0; fi
  if [ ! -t 0 ]; then return 1; fi
  local reply
  read -r -p "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy] ]]
}

# ---------------------------------------------------------------------------
# 1. Preflight
# ---------------------------------------------------------------------------
info "Preflight checks"

for cmd in git gh perl; do
  command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' is not installed."
done
ok "git, gh and perl are installed"

gh auth status >/dev/null 2>&1 || die "gh is not authenticated. Run 'gh auth login' and try again."
ok "gh is authenticated"

git rev-parse --show-toplevel >/dev/null 2>&1 || die "Not inside a git repository. Run this from a clone of the repository."
cd "$(git rev-parse --show-toplevel)"

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" \
  || die "Could not identify the GitHub repository for this clone."
DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)"
ok "Repository: $REPO (default branch: $DEFAULT_BRANCH)"

ECR_REGION_VALUE=""
if $SKIP_PREFLIGHT; then
  warn "Skipping the ECR variable and secret checks (--skip-preflight)"
else
  missing=()
  vars_json="$(gh variable list -R "$REPO" --json name,value -q '.[] | "\(.name)=\(.value)"' 2>/dev/null)" \
    || die "Could not list repository variables. You need write access to $REPO."
  for v in $REQUIRED_VARS; do
    value="$(printf '%s\n' "$vars_json" | sed -n "s/^$v=//p" | head -1)"
    if [ -n "$value" ]; then
      ok "Variable $v is set"
      [ "$v" = "ECR_REGION" ] && ECR_REGION_VALUE="$value"
    else
      fail "Variable $v is missing or empty"; missing+=("variable $v")
    fi
  done
  secrets="$(gh secret list -R "$REPO" --json name -q '.[].name' 2>/dev/null)" \
    || die "Could not list repository secrets. You need admin access to $REPO, or use --skip-preflight if you're sure they exist."
  if printf '%s\n' "$secrets" | grep -qx "$REQUIRED_SECRET"; then
    ok "Secret $REQUIRED_SECRET is set"
  else
    fail "Secret $REQUIRED_SECRET is missing"; missing+=("secret $REQUIRED_SECRET")
  fi
  if [ ${#missing[@]} -gt 0 ]; then
    echo
    die "Preflight failed. Provision the ECR repository with the Cloud Platform ECR module first, so these are created: ${missing[*]}.
If they are set at organisation level instead, re-run with --skip-preflight."
  fi
fi

[ -z "$(git status --porcelain)" ] || die "The working tree has uncommitted changes. Commit or stash them first."

# ---------------------------------------------------------------------------
# 2. Branch
# ---------------------------------------------------------------------------
info "Creating branch $BRANCH from origin/$DEFAULT_BRANCH"
git fetch --quiet origin "$DEFAULT_BRANCH"
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  die "Branch $BRANCH already exists locally. Delete it or use --branch NAME."
fi
if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  die "Branch $BRANCH already exists on origin, so this repository may already be (partly) migrated. Check it, or use --branch NAME."
fi
START_REF="$(git rev-parse --abbrev-ref HEAD)"
git switch --quiet --no-track -c "$BRANCH" "origin/$DEFAULT_BRANCH"
ok "On $BRANCH"

# ---------------------------------------------------------------------------
# 3. Helm --set path
# ---------------------------------------------------------------------------
# The --set path is wherever image.repository sits in the Helm values, for example
# 'image.repository' (custom charts) or 'generic-service.image.repository' (generic-service charts).
abandon_branch() {
  git switch --quiet "$START_REF" && git branch --quiet -D "$BRANCH"
  die "$1"
}
shopt -s nullglob
helm_values_files=(helm_deploy/*/values*.yaml helm_deploy/*/values*.yml helm_deploy/values*.yaml helm_deploy/values*.yml)
shopt -u nullglob
image_repo_refs=""
if [ ${#helm_values_files[@]} -gt 0 ]; then
  image_repo_refs="$(perl -ne '
    @s = () if $. == 1;
    my $at = "$ARGV:$.";
    close ARGV if eof;
    next if /^\s*(#|$)/ || /^\s*(---|\.\.\.)\s*$/;
    next unless /^(\s*)(-\s+)?(["\x27]?)([\w.-]+)\3\s*:(?:\s+(.*?))?\s*$/;
    my ($in, $key, $v) = (length($1) + length($2 // ""), $4, $5 // "");
    $v =~ s/\s+#.*$//;
    pop @s while @s && $s[-1][0] >= $in;
    print join(".", (map { $_->[1] } @s), $key), "\t$at\n" if $key eq "repository" && @s && $s[-1][1] eq "image";
    push @s, [$in, $key] if $v eq "" || $v =~ /^#/;
  ' "${helm_values_files[@]}")" || abandon_branch "Couldn't read the Helm values to find the image repository. Re-run with --helm-path PATH."
fi
detected_paths="$(printf '%s\n' "$image_repo_refs" | cut -f1 | sed '/^$/d' | sort -u)"
detected_count="$(printf '%s\n' "$detected_paths" | sed '/^$/d' | wc -l | tr -d ' ')"

if [ -n "$HELM_SET_PATH" ]; then
  if [ "$detected_count" -eq 1 ] && [ "$detected_paths" != "$HELM_SET_PATH" ]; then
    warn "--helm-path $HELM_SET_PATH differs from the image repository found in the Helm values ($detected_paths)"
  fi
elif [ "$detected_count" -eq 1 ]; then
  HELM_SET_PATH="$detected_paths"
  ok "Found the image repository at $HELM_SET_PATH ($(printf '%s\n' "$image_repo_refs" | cut -f2 | paste -sd, -))"
elif [ "$detected_count" -eq 0 ]; then
  abandon_branch "Couldn't find an image.repository key in helm_deploy/**/values*.yaml.
Re-run with --helm-path PATH, for example --helm-path image.repository or --helm-path generic-service.image.repository."
else
  printf '%s\n' "$image_repo_refs" | sed 's/^/      /'
  abandon_branch "Found more than one image repository path in the Helm values (above), so the --set path is ambiguous.
Re-run with --helm-path PATH to choose one."
fi
ok "Helm image override: --set $HELM_SET_PATH=<ECR registry>/<ECR repository>"

AWS_REGION_INPUT=""
if [ -n "$ECR_REGION_VALUE" ] && [ "$ECR_REGION_VALUE" != "eu-west-2" ]; then
  AWS_REGION_INPUT="yes"
fi

# ---------------------------------------------------------------------------
# YAML editor (perl, line based, keeps comments and formatting)
# ---------------------------------------------------------------------------
EDITOR_PL="$(mktemp -t ecr-migrate.XXXXXX)"
NOTES_FILE="$(mktemp -t ecr-notes.XXXXXX)"
trap 'rm -f "$EDITOR_PL" "$NOTES_FILE"' EXIT

cat >"$EDITOR_PL" <<'PERL'
use strict;
use warnings;

# Usage: perl editor.pl MODE FILE
#   MODE migrate : switch shared workflow calls to their ECR versions
#   MODE callers : add id-token: write for jobs calling locally modified workflows
# Env: HELM_SET_PATH, AWS_REGION_INPUT, MODIFIED_WORKFLOWS (comma separated basenames)
# Prints "CHANGED" to stdout if the file was modified; notes go to stderr.

my ($mode, $file) = @ARGV;
my $helm_path = $ENV{HELM_SET_PATH} || 'generic-service.image.repository';
my $aws_region = $ENV{AWS_REGION_INPUT} || '';
my %modified = map { $_ => 1 } grep { length } split /,/, ($ENV{MODIFIED_WORKFLOWS} || '');

my $REG    = '${{ vars.CLOUD_PLATFORM_ECR_REGISTRY_URL }}';
my $REPO   = '${{ vars.ECR_REPOSITORY }}';
my $SECRET = '${{ secrets.ECR_ROLE_TO_ASSUME }}';
my $SHARED = qr{ministryofjustice/hmpps-github-actions/\.github/workflows/};

open my $in, '<', $file or die "Cannot read $file: $!";
my @L = <$in>;
close $in;
chomp @L;
my $orig = join "\n", @L;
my %rank = (none => 0, read => 1, write => 2);

sub note   { print STDERR "NOTE|$file|$_[0]\n" }
sub manual { print STDERR "MANUAL|$file|$_[0]\n" }
sub ind    { my ($s) = @_; $s =~ /^( *)/; return length $1 }
sub blank  { $_[0] =~ /^\s*$/ }
sub cmt    { $_[0] =~ /^\s*#/ }

# ---- top-level permissions -------------------------------------------------
sub top_perms {
  my ($A) = @_;
  for my $i (0 .. $#$A) {
    next unless $A->[$i] =~ /^permissions:\s*(.*?)\s*(#.*)?$/;
    my $v = $1;
    return { idx => $i, scalar => $v } if $v ne '';
    my (%p, @order);
    my $j = $i + 1;
    while ($j <= $#$A && (blank($A->[$j]) || $A->[$j] =~ /^\s+/)) {
      if ($A->[$j] =~ /^\s+([\w-]+):\s*([\w-]+)/) { $p{$1} = $2; push @order, $1 }
      $j++;
    }
    return { idx => $i, map => \%p, order => \@order, end => $j };
  }
  return undef;
}

sub ensure_top_id_token {
  my ($A) = @_;
  my $tp = top_perms($A);
  if (!$tp) { manual("no top-level permissions block; make sure id-token: write is available to the jobs that need it"); return }
  if (defined $tp->{scalar}) {
    manual("top-level permissions is '$tp->{scalar}'; make sure it allows id-token: write") unless $tp->{scalar} eq 'write-all';
    return;
  }
  my $p = $tp->{map};
  return if ($p->{'id-token'} // '') eq 'write';
  my $child = 2;
  for my $k ($tp->{idx} + 1 .. $tp->{end} - 1) {
    if ($A->[$k] =~ /^(\s+)[\w-]+:/) { $child = length $1; last }
  }
  if (exists $p->{'id-token'}) {
    for my $k ($tp->{idx} + 1 .. $tp->{end} - 1) { $A->[$k] =~ s/^(\s+id-token:\s*)[\w-]+/${1}write/ }
  } else {
    my $last = $tp->{idx};
    for my $k ($tp->{idx} + 1 .. $tp->{end} - 1) { $last = $k unless blank($A->[$k]) }
    splice @$A, $last + 1, 0, (' ' x $child) . 'id-token: write';
  }
  note("added id-token: write to the top-level permissions");
}

# ---- job block helpers -----------------------------------------------------
# A job is { start, end (exclusive), P (property indent) }

sub job_keys {
  my ($A, $job) = @_;
  my %k;
  for my $i ($job->{start} + 1 .. $job->{end} - 1) {
    my $l = $A->[$i];
    next if blank($l) || cmt($l);
    if (ind($l) == $job->{P} && $l =~ /^\s*([\w-]+):\s*(.*?)\s*$/) { $k{$1} = $i unless exists $k{$1} }
  }
  return \%k;
}

sub child_range {
  # returns (first, end_exclusive, child_indent) for a mapping key at index $i
  my ($A, $job, $i) = @_;
  my $j = $i + 1;
  my $ci;
  while ($j < $job->{end}) {
    my $l = $A->[$j];
    if (!blank($l)) {
      last if ind($l) <= $job->{P};
      $ci //= ind($l) unless cmt($l);
    }
    $j++;
  }
  # don't swallow trailing blank lines
  my $e = $j;
  $e-- while $e > $i + 1 && blank($A->[$e - 1]);
  return ($i + 1, $e, $ci // $job->{P} + 2);
}

sub last_content_line {
  my ($A, $job) = @_;
  my $e = $job->{end} - 1;
  $e-- while $e > $job->{start} && blank($A->[$e]);
  return $e;
}

sub with_get {
  my ($A, $job, $key) = @_;
  my $k = job_keys($A, $job);
  return undef unless exists $k->{with};
  my ($f, $e, $ci) = child_range($A, $job, $k->{with});
  for my $i ($f .. $e - 1) {
    return $i if ind($A->[$i]) == $ci && $A->[$i] =~ /^\s*\Q$key\E:/;
  }
  return undef;
}

sub with_remove {
  my ($A, $job, $key) = @_;
  my $i = with_get($A, $job, $key);
  return 0 unless defined $i;
  splice @$A, $i, 1;
  $job->{end}--;
  return 1;
}

sub with_add {
  my ($A, $job, $key, $value) = @_;
  my $k = job_keys($A, $job);
  if (exists $k->{with}) {
    my ($f, $e, $ci) = child_range($A, $job, $k->{with});
    splice @$A, $e, 0, (' ' x $ci) . "$key: $value";
  } else {
    my $at = last_content_line($A, $job) + 1;
    splice @$A, $at, 0, (' ' x $job->{P}) . 'with:', (' ' x ($job->{P} + 2)) . "$key: $value";
    $job->{end}++;
  }
  $job->{end}++;
}

sub ensure_secret {
  my ($A, $job) = @_;
  my $k = job_keys($A, $job);
  if (exists $k->{secrets}) {
    my $l = $A->[$k->{secrets}];
    return if $l =~ /secrets:\s*inherit\b/;
    my ($f, $e, $ci) = child_range($A, $job, $k->{secrets});
    for my $i ($f .. $e - 1) { return if $A->[$i] =~ /^\s*ECR_ROLE_TO_ASSUME:/ }
    splice @$A, $e, 0, (' ' x $ci) . "ECR_ROLE_TO_ASSUME: $SECRET";
    $job->{end}++;
  } else {
    my $at = last_content_line($A, $job) + 1;
    splice @$A, $at, 0, (' ' x $job->{P}) . 'secrets:', (' ' x ($job->{P} + 2)) . "ECR_ROLE_TO_ASSUME: $SECRET";
    $job->{end} += 2;
  }
}

sub ensure_perms {
  # $need: [[key, level], ...] required on an existing block
  # $new:  [[key, level], ...] used (merged with top-level) when there is no block
  my ($A, $job, $tp, $need, $new, $name) = @_;
  my $k = job_keys($A, $job);
  if (exists $k->{permissions}) {
    my $i = $k->{permissions};
    if ($A->[$i] =~ /permissions:\s*([^\s#].*?)\s*(#.*)?$/) {
      my $v = $1;
      manual("job '$name' has 'permissions: $v'; make sure it allows id-token: write") unless $v eq 'write-all';
      return;
    }
    my ($f, $e, $ci) = child_range($A, $job, $i);
    for my $req (@$need) {
      my ($key, $lvl) = @$req;
      my $found;
      for my $j ($f .. $e - 1) {
        if ($A->[$j] =~ /^(\s*)\Q$key\E:\s*([\w-]+)(.*)$/) {
          $found = 1;
          if (($rank{$2} // 0) < $rank{$lvl}) { $A->[$j] = "$1$key: $lvl$3" }
        }
      }
      if (!$found) { splice @$A, $e, 0, (' ' x $ci) . "$key: $lvl"; $e++; $job->{end}++ }
    }
    return;
  }
  my (@order, %lvl);
  if ($tp && $tp->{map}) {
    for my $key (@{ $tp->{order} }) { push @order, $key; $lvl{$key} = $tp->{map}{$key} }
  } else {
    manual("job '$name' had no permissions block and the workflow has no top-level permissions map; added a job block, so check nothing it previously inherited is now missing");
  }
  for my $req (@$new) {
    my ($key, $l) = @$req;
    if (!exists $lvl{$key}) { push @order, $key; $lvl{$key} = $l }
    elsif (($rank{$lvl{$key}} // 0) < $rank{$l}) { $lvl{$key} = $l }
  }
  my @block = ((' ' x $job->{P}) . 'permissions:', map { (' ' x ($job->{P} + 2)) . "$_: $lvl{$_}" } @order);
  my $at = exists $k->{with} ? $k->{with} : last_content_line($A, $job) + 1;
  splice @$A, $at, 0, @block;
  $job->{end} += @block;
}

sub ensure_helm_args {
  my ($A, $job, $name) = @_;
  my $set = "--set $helm_path=$REG/$REPO";
  my $i = with_get($A, $job, 'helm_additional_args');
  if (!defined $i) { with_add($A, $job, 'helm_additional_args', "'$set'"); return }
  my $l = $A->[$i];
  return if $l =~ /(^|[\s'"])\Q$helm_path\E=/;
  if ($l =~ /([\w.-]*image\.repository)=/) {
    manual("job '$name' already sets --set $1=..., but the Helm values have the image repository at $helm_path; fix it by hand");
    return;
  }
  $l =~ /^(\s*helm_additional_args:\s*)(.*)$/;
  my ($pre, $v) = ($1, $2);
  if ($v =~ /^'(.*)'(\s*#.*)?$/) {
    $A->[$i] = $pre . "'" . $set . ($1 ne '' ? " $1" : '') . "'" . ($2 // '');
  } elsif ($v =~ /^"(.*)"(\s*#.*)?$/) {
    $A->[$i] = $pre . '"' . $set . ($1 ne '' ? " $1" : '') . '"' . ($2 // '');
  } elsif ($v eq '' || $v =~ /^[|>]/) {
    manual("job '$name' has a multi-line helm_additional_args; add '$set' to it by hand");
  } else {
    $A->[$i] = $pre . "'" . $set . " $v'";
  }
}

# ---- migrate one job ---------------------------------------------------------
sub migrate_job {
  my ($A, $job, $tp, $name) = @_;
  my $k = job_keys($A, $job);
  return 0 unless exists $k->{uses};
  my $u = $k->{uses};
  return 0 unless $A->[$u] =~ $SHARED;
  my ($wf) = $A->[$u] =~ m{/workflows/([\w.-]+?)\.ya?ml@};
  return 0 unless defined $wf;

  if ($wf eq 'docker_build' || $wf eq 'docker_push') {
    $A->[$u] =~ s{/workflows/$wf\.yml@}{/workflows/${wf}_ecr.yml@};
    with_remove($A, $job, 'docker_registry');
    with_remove($A, $job, 'registry_org');
    if ($wf eq 'docker_push') {
      with_add($A, $job, 'ecr_repository', '${{ vars.ECR_REPOSITORY }}') unless defined with_get($A, $job, 'ecr_repository');
      with_add($A, $job, 'ecr_registry_url', '${{ vars.CLOUD_PLATFORM_ECR_REGISTRY_URL }}') unless defined with_get($A, $job, 'ecr_registry_url');
      with_add($A, $job, 'aws_region', '${{ vars.ECR_REGION }}') if $aws_region && !defined with_get($A, $job, 'aws_region');
      note("job '$name': docker_push -> docker_push_ecr; check the inputs against docker_push_ecr.yml");
    }
    ensure_secret($A, $job);
    ensure_perms($A, $job, $tp, [['id-token', 'write']],
      [['contents', 'read'], ['packages', 'write'], ['id-token', 'write'], ['attestations', 'write']], $name);
    return 1;
  }
  if ($wf eq 'deploy_env' || $wf eq 'deploy_to_env') {
    $A->[$u] =~ s{/workflows/deploy_env\.yml@}{/workflows/deploy_to_env.yml@};
    ensure_helm_args($A, $job, $name);
    ensure_perms($A, $job, $tp, [['contents', 'read'], ['id-token', 'write']],
      [['contents', 'read'], ['id-token', 'write']], $name);
    return 1;
  }
  if ($wf eq 'security_snyk_scan' || $wf eq 'security_snyk_scan_private') {
    $A->[$u] =~ s{/workflows/$wf\.yml@}{/workflows/security_snyk_scan_ecr.yml@};
    with_add($A, $job, 'image_ref', "'$REG/$REPO:latest'") unless defined with_get($A, $job, 'image_ref');
    ensure_secret($A, $job);
    ensure_perms($A, $job, $tp, [['id-token', 'write']], [['contents', 'read'], ['id-token', 'write']], $name);
    note("job '$name': $wf -> security_snyk_scan_ecr") if $wf eq 'security_snyk_scan_private';
    return 1;
  }
  return 0;
}

sub caller_job {
  my ($A, $job, $tp, $name) = @_;
  my $k = job_keys($A, $job);
  return 0 unless exists $k->{uses};
  my ($local) = $A->[$k->{uses}] =~ m{uses:\s*\./\.github/workflows/([\w.-]+)};
  return 0 unless $local && $modified{$local};
  if (exists $k->{permissions}) {
    ensure_perms($A, $job, $tp, [['id-token', 'write']], [], $name);
  } else {
    ensure_top_id_token($A);
  }
  note("job '$name' calls local workflow $local, which now needs id-token: write");
  return 1;
}

# ---- process all jobs in an array (bottom up, so inserts don't shift) -------
sub process {
  my ($A, $tp, $fn) = @_;
  my ($jobs) = grep { $A->[$_] =~ /^jobs:\s*(#.*)?$/ } 0 .. $#$A;
  return 0 unless defined $jobs;
  my $J;
  for my $i ($jobs + 1 .. $#$A) {
    next if blank($A->[$i]) || cmt($A->[$i]);
    $J = ind($A->[$i]); last;
  }
  return 0 unless defined $J && $J > 0;
  my @starts = grep { $A->[$_] =~ /^ {$J}([\w.-]+):\s*(#.*)?$/ } $jobs + 1 .. $#$A;
  my $changed = 0;
  for my $s (reverse @starts) {
    my $e = $s + 1;
    $e++ while $e <= $#$A && (blank($A->[$e]) || cmt($A->[$e]) || ind($A->[$e]) > $J);
    # trailing comments at job level or shallower (e.g. a commented-out job) aren't part of this job
    $e-- while $e > $s + 1 && (blank($A->[$e - 1]) || (cmt($A->[$e - 1]) && ind($A->[$e - 1]) <= $J));
    my $P;
    for my $i ($s + 1 .. $e - 1) { next if blank($A->[$i]) || cmt($A->[$i]); $P = ind($A->[$i]); last }
    next unless defined $P;
    my ($name) = $A->[$s] =~ /^\s*([\w.-]+):/;
    $changed += $fn->($A, { start => $s, end => $e, P => $P }, $tp, $name);
  }
  return ($changed, $J);
}

my $tp = top_perms(\@L);
my $fn = $mode eq 'callers' ? \&caller_job : \&migrate_job;
my ($changed, $J) = process(\@L, $tp, $fn);

# Commented-out jobs: uncomment each run of comment lines at job indent or shallower,
# migrate the jobs in it, then re-comment in the same style.
if ($mode eq 'migrate' && defined $J) {
  my ($jobs) = grep { $L[$_] =~ /^jobs:\s*(#.*)?$/ } 0 .. $#L;
  my $i = defined $jobs ? $jobs + 1 : scalar @L;
  my $is_c = sub { $_[0] =~ /^( *)#/ && length($1) <= $J };
  while ($i <= $#L) {
    if ($is_c->($L[$i])) {
      my $s = $i;
      $i++ while $i <= $#L && $is_c->($L[$i]);
      my @run = @L[$s .. $i - 1];
      next unless grep { /uses:.*$SHARED(docker_build|docker_push|deploy_env|deploy_to_env|security_snyk_scan|security_snyk_scan_private)\.yml/ } @run;
      $run[0] =~ /^( *)#/;
      my $p = length $1;
      my $uncomment = sub {
        my $x = shift;
        $x =~ /^ *#/ or return $x;
        if ($p == $J) { $x =~ s/^( *)# ?/$1/ } else { $x =~ s/^( *)#/$1/ }
        return $x;
      };
      my $recomment = sub {
        my $x = shift;
        if ($p == $J) {
          return (' ' x $J) . '#' if $x =~ /^\s*$/;
          $x =~ s/^( {$J})/$1# /;
          return $x;
        }
        return (' ' x $p) . '#' if $x =~ /^\s*$/;
        return (' ' x $p) . '#' . substr($x, $p);
      };
      my @frag = ('jobs:', map { $uncomment->($_) } @run);
      my ($c) = process(\@frag, $tp, \&migrate_job);
      next unless $c;
      shift @frag;
      my @back = map { $recomment->($_) } @frag;
      next if join("\n", @back) eq join("\n", @run);
      splice @L, $s, $i - $s, @back;
      $i = $s + @back;
      $changed += $c;
      note("updated $c commented-out job(s); check them before you uncomment them");
    } else {
      $i++;
    }
  }
}

# A reusable workflow (workflow_call) that now calls ECR workflows needs id-token from its callers.
if ($mode eq 'migrate' && $changed && grep { /^\s+workflow_call:/ } @L) {
  ensure_top_id_token(\@L);
}

my $new = join "\n", @L;
if ($new ne $orig) {
  open my $out, '>', $file or die "Cannot write $file: $!";
  print $out "$new\n";
  close $out;
  print "CHANGED\n";
}
PERL

run_editor() {
  HELM_SET_PATH="$HELM_SET_PATH" AWS_REGION_INPUT="$AWS_REGION_INPUT" MODIFIED_WORKFLOWS="${MODIFIED_WORKFLOWS:-}" \
    perl "$EDITOR_PL" "$1" "$2" 2>>"$NOTES_FILE"
}

# ---------------------------------------------------------------------------
# 4. Workflows
# ---------------------------------------------------------------------------
info "Updating workflows"
shopt -s nullglob
workflow_files=(.github/workflows/*.yml .github/workflows/*.yaml)
shopt -u nullglob
TARGET_RE='hmpps-github-actions/\.github/workflows/(docker_build|docker_push|deploy_env|deploy_to_env|security_snyk_scan|security_snyk_scan_private)\.yml'

changed_files=()
MODIFIED_WORKFLOWS=""
for f in ${workflow_files[@]+"${workflow_files[@]}"}; do
  grep -Eq "$TARGET_RE" "$f" || continue
  if [ "$(run_editor migrate "$f")" = "CHANGED" ]; then
    changed_files+=("$f")
    MODIFIED_WORKFLOWS="${MODIFIED_WORKFLOWS:+$MODIFIED_WORKFLOWS,}$(basename "$f")"
    ok "$f"
  fi
done

# Workflows that call the local workflows we just changed need id-token: write too.
if [ -n "$MODIFIED_WORKFLOWS" ]; then
  for f in ${workflow_files[@]+"${workflow_files[@]}"}; do
    grep -Eq 'uses:[[:space:]]*\./\.github/workflows/' "$f" || continue
    if [ "$(run_editor callers "$f")" = "CHANGED" ]; then
      ok "$f (calls a changed local workflow)"
      changed_files+=("$f")
    fi
  done
fi

# ---------------------------------------------------------------------------
# 5. Helm values
# ---------------------------------------------------------------------------
info "Updating Helm values"
shopt -s nullglob
values_files=(helm_deploy/*/values*.yaml helm_deploy/values*.yaml)
shopt -u nullglob
for f in ${values_files[@]+"${values_files[@]}"}; do
  if grep -Eq '^[[:space:]]*repository:[[:space:]]*["'\'']?ghcr\.io/' "$f"; then
    perl -pi -e 's/^(\s*repository:\s*)["\x27]?ghcr\.io\/\S*.*$/${1}ecr_repository # override at deployment time/' "$f"
    ok "$f"
    changed_files+=("$f")
  fi
done

# ---------------------------------------------------------------------------
# 6. Checks
# ---------------------------------------------------------------------------
info "Checking"
if [ ${#changed_files[@]} -eq 0 ]; then
  warn "Nothing to change: no GHCR shared workflow calls or ghcr.io Helm values found."
  early_manual="$(sort -u "$NOTES_FILE" | grep '^MANUAL|' | cut -d'|' -f2- | sed 's/|/: /' || true)"
  if [ -n "$early_manual" ]; then info "${YELLOW}Needs a manual check${RESET}"; printf '%s\n' "$early_manual" | sed 's/^/  - /'; fi
  git switch --quiet "$START_REF" && git branch --quiet -D "$BRANCH"
  echo "Removed the empty branch $BRANCH. The repository may already be migrated."
  exit 0
fi

leftover="$(grep -nE 'hmpps-github-actions/\.github/workflows/(docker_build|docker_push|deploy_env|security_snyk_scan|security_snyk_scan_private)\.yml' .github/workflows/* 2>/dev/null || true)"
if [ -n "$leftover" ]; then
  fail "Old shared workflow references remain (update these by hand):"
  printf '      %s\n' "$leftover"
  echo "MANUAL|-|old shared workflow references remain; see the script output" >>"$NOTES_FILE"
else
  ok "No old shared workflow references remain"
fi

other_refs="$(grep -nE 'uses:[[:space:]]*[^.[:space:]][^@]*/\.github/workflows/[^@]*(docker|deploy|snyk)[^@]*@' .github/workflows/* 2>/dev/null | grep -v 'ministryofjustice/hmpps-github-actions/' || true)"
if [ -n "$other_refs" ]; then
  warn "These call build/deploy/Snyk workflows from another repository, which the script doesn't change. Check whether they need the ECR changes:"
  printf '      %s\n' "$other_refs"
  while IFS= read -r l; do echo "MANUAL|${l%%:*}|calls a non-standard shared workflow; check whether it needs the ECR changes: $(echo "${l#*uses:}" | sed 's/^ *//')" >>"$NOTES_FILE"; done <<<"$other_refs"
fi

ghcr_refs="$(git grep -nIi 'ghcr' -- . ':!*.md' 2>/dev/null || true)"
if [ -n "$ghcr_refs" ]; then
  warn "Remaining GHCR references (not changed). Base images (FROM ghcr.io/...) will need authentication to pull if those packages become internal; ghcr-pull-secret / imagePullSecrets can be removed once the app deploys from ECR:"
  printf '      %s\n' "$ghcr_refs"
fi

changed_workflows=()
for f in ${changed_files[@]+"${changed_files[@]}"}; do
  case "$f" in .github/workflows/*) changed_workflows+=("$f") ;; esac
done
if command -v actionlint >/dev/null 2>&1; then
  if [ ${#changed_workflows[@]} -eq 0 ] || actionlint "${changed_workflows[@]}"; then
    ok "actionlint passed"
  else
    warn "actionlint reported issues (above)"
  fi
else
  warn "actionlint isn't installed, so the workflows weren't linted (brew install actionlint)"
fi

if command -v ruby >/dev/null 2>&1; then
  bad=0
  for f in "${changed_files[@]}"; do
    ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$f" 2>/dev/null || { fail "$f is not valid YAML"; bad=1; }
  done
  [ $bad -eq 0 ] && ok "Changed files parse as YAML"
fi

echo
info "Changes"
git --no-pager diff --stat
echo
git --no-pager diff

notes="$(sort -u "$NOTES_FILE" | grep '^NOTE|' | cut -d'|' -f2- | sed 's/|/: /' || true)"
manual="$(sort -u "$NOTES_FILE" | grep '^MANUAL|' | cut -d'|' -f2- | sed 's/|/: /' || true)"
echo
if [ -n "$notes" ]; then info "Notes"; printf '%s\n' "$notes" | sed 's/^/  - /'; fi
if [ -n "$manual" ]; then info "${YELLOW}Needs a manual check${RESET}"; printf '%s\n' "$manual" | sed 's/^/  - /'; fi
cat <<EOF

${BOLD}Before merging, check:${RESET}
  - The Helm override uses --set $HELM_SET_PATH. Make sure your chart reads that value.
  - Job permissions: any job that gained a permissions block now gets only what's listed.
  - Run the pipeline on the branch (open a PR); that is the real test.
  - After it's merged and deployed from ECR, the repository can be made internal.
EOF

# ---------------------------------------------------------------------------
# 7. Commit, push, PR
# ---------------------------------------------------------------------------
echo
if ! confirm "Commit these changes?"; then
  echo "Left the changes uncommitted on $BRANCH."
  exit 0
fi
git add -A .github helm_deploy 2>/dev/null || git add -A
git commit --quiet -m "Migrate build, deploy and Snyk workflows from GHCR to ECR"
ok "Committed $(git rev-parse --short HEAD)"

if ! confirm "Push $BRANCH to origin?"; then
  echo "Committed locally; not pushed."
  exit 0
fi
git push --quiet -u origin "$BRANCH"
ok "Pushed"

if ! confirm "Open a pull request?"; then
  echo "Pushed. Open a PR when ready: https://github.com/$REPO/pull/new/$BRANCH"
  exit 0
fi
body="$(cat <<EOF
Migrates the build, deploy and Snyk workflows from GHCR to ECR, so the repository can be made internal.

Generated by \`migrate-ghcr-to-ecr.sh\`.

- \`docker_build\` → \`docker_build_ecr\` (registry inputs removed, \`ECR_ROLE_TO_ASSUME\` secret and \`id-token: write\` added)
- \`deploy_env\` → \`deploy_to_env\`, with \`--set $HELM_SET_PATH=<ECR registry>/<ECR repository>\`
- \`security_snyk_scan\` → \`security_snyk_scan_ecr\`, with \`image_ref\`
- Helm \`image.repository\` → \`ecr_repository\` placeholder

${manual:+### Needs a manual check
$(printf '%s\n' "$manual" | sed 's/^/- /')
}
EOF
)"
gh pr create --repo "$REPO" --head "$BRANCH" --base "$DEFAULT_BRANCH" \
  --title "Migrate build, deploy and Snyk workflows from GHCR to ECR" --body "$body"
