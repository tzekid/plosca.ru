# Use the Arch Linux base image for linux/amd64 architecture
FROM --platform=linux/amd64 archlinux:latest as builder

# Install required packages: git, base-devel, wget, and zig
RUN pacman -Syu --noconfirm 
RUN pacman -S --noconfirm git base-devel wget zig 

# clone the repository
WORKDIR /app
# RUN git clone https://github.com/tzekid/plosca.ru /app  --depth 1 

COPY . .

# # Copy static folder, src and build.zig build.zig.zon to the working directory
# COPY static /app/static
# COPY src /app/src
# COPY build.zig /app/build.zig
# COPY build.zig.zon /app/build.zig.zon

# go to the working directory
# RUN cd /app

# Build the executable using zig
RUN zig build -Drelease-fast

# RUN pacman -Rns --noconfirm git base-devel wget zig
# RUN pacman -Scc --noconfir


FROM --platform=linux/amd64 archlinux:latest as builder
WORKDIR /app
COPY --from=builder /app/zig-out/bin/tzekid_website /app/tzekid_website

# Expose port 3000
EXPOSE 3000

# Run the executable from the root of the repository
CMD ["/app/tzekid_website"]

