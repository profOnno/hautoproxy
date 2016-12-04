# Hautoproxy

HAProxy for docker with auto adding containers to cname (SNI) host. Can use with Letsencrypt. Work In Progress..

## Util
### /util/doget.lua

`util/doget.lua /containers/json` will do a http request on `/var/run/docker.sock` ane return json data.
Use the `jq` command to filter the result. 
Example: `util/doget.lua /containers/json | jq .[].Names`
```
[
	"/compassionate_gates"
]
[
	"/gogs4"
]
[
	"/kickass_yonath"
]
[
	"/hautoproxy"
]
[
	"/thirsty_engelbart"
]
[
	"/prickly_galileo"
]
```
