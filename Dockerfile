FROM --platform=linux/amd64 archlinux:latest

RUN pacman -Syu --noconfirm 
RUN pacman -S --noconfirm git base-devel wget zig  curl 

WORKDIR /app

COPY . .

RUN zig build

EXPOSE 3210

CMD ["/app/zig-out/bin/tzekid_website"]

