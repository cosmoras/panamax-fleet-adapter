FROM centurylink/ruby-base:2.1.2

EXPOSE 9292

ADD . /var/app/fleet-adapter
WORKDIR /var/app/fleet-adapter
RUN bundle install

CMD ["rackup", "-E production"]
