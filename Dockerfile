# syntax=docker/dockerfile:1
FROM nginx:1.27-alpine

# Static placeholder — replaces the default welcome page.
COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
