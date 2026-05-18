# Package Repository

Package repository for [rushikeshsakharleofficial](https://github.com/rushikeshsakharleofficial) tools.
Hosted on GitHub Pages at `https://rushikeshsakharleofficial.github.io/packages/`

---

## code-outline-graph-go

Go code indexing and search MCP server.

### Debian / Ubuntu (apt)

```bash
curl -fsSL https://rushikeshsakharleofficial.github.io/packages/apt/gpg.key \
  | sudo tee /etc/apt/trusted.gpg.d/rushikesh.asc
echo "deb [arch=amd64] https://rushikeshsakharleofficial.github.io/packages/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/rushikesh.list
sudo apt update
sudo apt install code-outline-graph-go
```

### RHEL / Fedora / CentOS (dnf/yum)

```bash
sudo curl -fsSL https://rushikeshsakharleofficial.github.io/packages/rpm/rushikesh.repo \
  -o /etc/yum.repos.d/rushikesh.repo
sudo dnf install code-outline-graph-go
# or: sudo yum install code-outline-graph-go
```

### openSUSE (zypper)

```bash
sudo zypper addrepo https://rushikeshsakharleofficial.github.io/packages/rpm/rushikesh.repo
sudo zypper install code-outline-graph-go
```

### Alpine Linux (apk)

```bash
echo "https://rushikeshsakharleofficial.github.io/packages/apk/edge/main" \
  | sudo tee -a /etc/apk/repositories
# Download and trust the public key
curl -fsSL https://rushikeshsakharleofficial.github.io/packages/apk/rushikesh.rsa.pub \
  -o /etc/apk/keys/rushikesh.rsa.pub
sudo apk update
sudo apk add code-outline-graph-go
```

### Any platform (install script)

```bash
curl -fsSL https://raw.githubusercontent.com/rushikeshsakharleofficial/gocode-outline-graph/main/install.sh | bash
```
