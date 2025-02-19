#!/usr/bin/env bash

# This script comprises everything up to and including the boilerplate
# backing image at version image-v2.0.0. It is used when performing a
# full build in the appsre pipeline, but is bypassed during presubmit CI
# in prow to make testing faster there. As such, there is a (very small)
# possibility of those behaving slightly differently.

set -x
set -euo pipefail

tmpd=$(mktemp -d)
pushd $tmpd

###############
# golangci-lint
###############
GOCILINT_VERSION="1.31.0"
GOCILINT_SHA256SUM="9a5d47b51442d68b718af4c7350f4406cdc087e2236a5b9ae52f37aebede6cb3"
GOCILINT_LOCATION=https://github.com/golangci/golangci-lint/releases/download/v${GOCILINT_VERSION}/golangci-lint-${GOCILINT_VERSION}-linux-amd64.tar.gz

curl -L -o golangci-lint.tar.gz $GOCILINT_LOCATION
echo ${GOCILINT_SHA256SUM} golangci-lint.tar.gz | sha256sum -c
tar xzf golangci-lint.tar.gz golangci-lint-${GOCILINT_VERSION}-linux-amd64/golangci-lint
mv golangci-lint-${GOCILINT_VERSION}-linux-amd64/golangci-lint /usr/local/bin

###############
# Set up go env
###############
# Get rid of -mod=vendor
unset GOFLAGS
# No, really, we want to use modules
export GO111MODULE=on

###########
# kustomize
###########
KUSTOMIZE_VERSION=v4.5.3
go install sigs.k8s.io/kustomize/kustomize/${KUSTOMIZE_VERSION%%.*}@${KUSTOMIZE_VERSION}

################
# controller-gen
################
# v0.3.0 is used by the old operator-sdk, v0.8.0 is used by the latest
CONTROLLER_GEN_VERSIONS="v0.3.0 v0.8.0"
for CONTROLLER_GEN_VERSION in $CONTROLLER_GEN_VERSIONS;do
    go install sigs.k8s.io/controller-tools/cmd/controller-gen@${CONTROLLER_GEN_VERSION}
    mv $GOPATH/bin/controller-gen $GOPATH/bin/controller-gen-${CONTROLLER_GEN_VERSION}
done
# We set the v0.3.0 as default
ln -s $GOPATH/bin/controller-gen-v0.3.0 $GOPATH/bin/controller-gen

#############
# openapi-gen
#############
OPENAPI_GEN_VERSIONS="v0.19.4 v0.23.0"
for OPENAPI_GEN_VERSION in $OPENAPI_GEN_VERSIONS;do
    go install k8s.io/code-generator/cmd/openapi-gen@${OPENAPI_GEN_VERSION}
    mv $GOPATH/bin/openapi-gen $GOPATH/bin/openapi-gen-${OPENAPI_GEN_VERSION}
done
# Set v0.19.4 as the default version for backwards compatibility
ln -s $GOPATH/bin/openapi-gen-v0.19.4 $GOPATH/bin/openapi-gen

#########
# ENVTEST
#########
# We do not enforce versioning on setup-envtest
go install sigs.k8s.io/controller-runtime/tools/setup-envtest@latest

# mockgen
#########
MOCKGEN_VERSION=v1.4.4
go install github.com/golang/mock/mockgen@${MOCKGEN_VERSION}

############
# go-bindata
############
GO_BINDATA_VERSION=v3.1.2
go install github.com/go-bindata/go-bindata/...@${GO_BINDATA_VERSION}

# HACK: `go get` creates lots of things under GOPATH that are not group
# accessible, even if umask is set properly. This causes failures of
# subsequent go tool usage (e.g. resolving packages) by a non-root user,
# which is what consumes this image in CI.
# Here we make group permissions match user permissions, since the CI
# non-root user's gid is 0.
dir=$(go env GOPATH)
for bit in r x w; do
    find $dir -perm -u+${bit} -a ! -perm -g+${bit} -exec chmod g+${bit} '{}' +
done

####
# yq
####
YQ_VERSION="3.4.1"
YQ_SHA256SUM="adbc6dd027607718ac74ceac15f74115ac1f3caef68babfb73246929d4ffb23c"
YQ_LOCATION=https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64

curl -L -o yq $YQ_LOCATION
echo ${YQ_SHA256SUM} yq | sha256sum -c
chmod ugo+x yq
mv yq /usr/local/bin

##################
# python libraries
##################
python3 -m pip install PyYAML==5.3.1

#########
# cleanup
#########
yum clean all
yum -y autoremove

# autoremove removes ssh (which it presumably wouldn't if we were able
# to install git from a repository, because git has a dep on ssh.)
# Do we care to restrict this to a particular version?
yum -y install openssh-clients

rm -rf /var/cache/yum

popd
rm -fr $tmpd
