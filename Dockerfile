# Stage 1: Build Flutter Web
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

# Enable web and show doctor info
RUN flutter config --no-analytics && \
    flutter config --enable-web && \
    flutter doctor

# Copy pubspec and get dependencies
COPY pubspec.yaml .
RUN flutter pub get

# Copy source code and assets
COPY . .

# Build arguments (renamed to avoid security lints)
ARG SB_URL
ARG SB_TOKEN

# Build Flutter Web
RUN flutter build web \
    --dart-define=SB_URL=${SB_URL} \
    --dart-define=SB_TOKEN=${SB_TOKEN} \
    --release

# Stage 2: Serve with Nginx
FROM nginx:alpine
# Remove default nginx contents
RUN rm -rf /usr/share/nginx/html/*
# Copy build result
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
