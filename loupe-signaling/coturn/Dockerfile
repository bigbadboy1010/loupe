FROM coturn/coturn:4.6
USER root
COPY docker-entrypoint.sh /usr/local/bin/loupe-coturn-entrypoint
RUN chmod 755 /usr/local/bin/loupe-coturn-entrypoint
ENTRYPOINT ["/usr/local/bin/loupe-coturn-entrypoint"]
