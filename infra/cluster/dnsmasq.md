# Wildcard `*.test` → `127.0.0.1` (one line)

The shared Traefik routes by `Host()` header, so every project just needs its
`<name>.test` hostname to resolve to localhost. One dnsmasq wildcard covers
**all** projects forever — a new project needs **zero** DNS edits.

The whole config is one line:

```
address=/test/127.0.0.1
```

Pick the setup that matches your machine.

## Standalone dnsmasq (most Linux, incl. Arch)

```bash
echo 'address=/test/127.0.0.1' | sudo tee /etc/dnsmasq.d/test.conf
sudo systemctl restart dnsmasq
```

Make sure your resolver actually consults dnsmasq (e.g. `/etc/resolv.conf`
points at `127.0.0.1`, or dnsmasq is your system resolver).

## NetworkManager's built-in dnsmasq (common on Arch desktops)

If `/etc/NetworkManager/NetworkManager.conf` has `dns=dnsmasq` under `[main]`:

```bash
echo 'address=/test/127.0.0.1' | sudo tee /etc/NetworkManager/dnsmasq.d/test.conf
sudo systemctl reload NetworkManager
```

## systemd-resolved

`resolved` has no wildcard-domain support. Run dnsmasq alongside it: bind dnsmasq
to `127.0.0.1` with the line above, then point `resolved` at it as upstream, or
set dnsmasq first in the resolver order. The standalone setup above is simpler.

## macOS

```bash
brew install dnsmasq
echo 'address=/test/127.0.0.1' >> $(brew --prefix)/etc/dnsmasq.conf
sudo brew services restart dnsmasq
sudo mkdir -p /etc/resolver
echo 'nameserver 127.0.0.1' | sudo tee /etc/resolver/test
```

## Verify

```bash
getent hosts foo.test      # -> 127.0.0.1 foo.test   (or: dig +short foo.test)
```

---

### Note: point `kubectl` at your cluster

`make cluster-init` runs `kubectl` against your **current context**. On a fresh
MicroK8s box the host `kubectl` has no context — wire it once:

```bash
microk8s config >> ~/.kube/config      # then `kubectl config use-context microk8s`
```

…or run cluster-init against MicroK8s's own kubectl:

```bash
make cluster-init KUBECTL="microk8s kubectl"
```
