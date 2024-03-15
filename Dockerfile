FROM nginx:1.21.1
RUN rm /etc/nginx/nginx.conf
CMD [ "nginx", "-g", "daemon off;"]