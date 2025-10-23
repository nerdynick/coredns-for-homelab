# CoreDNS for Homelab

This is a custome build of CoreDNS that I used within my homelab. 
It's intent is to include all the plugins I used to help automate much of the DNS resolution and other things within the homelab and just self-hosted services. 
If you find some additional plugins that you think I should include. Please feel free to open an Issue or PR for the changes. Also open to learning about other plugins out there that might assist in running an even smarter DNS services at home.

# The Plugins

## Traefik

The (scottt732/coredns-traefik)[https://github.com/scottt732/coredns-traefik] plugin allows you to call the API of your Traefik instance(s) to discover services and their addresses. 

This plugin:
> Extracts FQDN's from the Host() and HostSNI() values in traefik's http router rules (Traefik's /api/http/routers endpoint). Returns a CNAME result with the traefik instance's domain.

What's great about this plugin is that you can pair it with Traefiks Docker provider, for example, to 1st auto discover your docker containers, their exposed ports, TLS settings, and what address(es) it is looking to be exposed as via Traefik and Docker Labels. With those containers/services now discovered, proxed, and hopefully now TLS enabled, this plugin then setups all the DNS configs to enable calling those services. 

*NOTE:* I have plans to publish a Blog/Video show caseing how to set this up. Stay tuned for when that goes live.

## k8s_gateway

The (k8s_gateway)[https://github.com/k8s-gateway/k8s_gateway] plugin is my prefered avenue for providing DNS resolution for externally exposed Kubernetes services and more. 

While I include this plugin in this build, the developers publish their own docker images with each update/release. Their image is a much more stripped down version, which might be more ideal for usage as a single sub-zoned resolution for just your K8s services. 