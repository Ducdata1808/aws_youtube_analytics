-- Automatically create database if not exists
CREATE DATABASE IF NOT EXISTS youtube_analytics;

-- 1. Main Fact table: Trending videos details (Using wildcard **/*.parquet to scan all country partitions)
CREATE TABLE IF NOT EXISTS youtube_analytics.fact_trending_videos
(
    video_id           String,
    country            String,
    trending_date      Date,
    title              String,
    channel_title      String,
    category_name      String,
    publish_date       Date,
    publish_hour       UInt8,
    views              UInt64,
    likes              UInt64,
    dislikes           UInt64,
    comment_count      UInt64,
    engagement_rate    Float64,
    like_ratio         Float64,
    tags_count         UInt32,
    title_length       UInt32,
    comments_disabled  UInt8,
    ratings_disabled   UInt8
)
ENGINE = S3('http://localstack:4566/yt-analytics-bucket/fact_trending_videos/**/*.parquet', 'test', 'test', 'Parquet');

-- 2. Aggregate table: Performance statistics by Category
CREATE TABLE IF NOT EXISTS youtube_analytics.agg_category_stats
(
    country              String,
    category_name        String,
    total_videos         UInt64,
    avg_views            Float64,
    avg_likes            Float64,
    avg_engagement_rate  Float64,
    total_views          UInt64,
    max_views            UInt64
)
ENGINE = S3('http://localstack:4566/yt-analytics-bucket/agg_category_stats/*.parquet', 'test', 'test', 'Parquet');

-- 3. Bảng Aggregate: Performance statistics by Channel
CREATE TABLE IF NOT EXISTS youtube_analytics.agg_channel_performance
(
    country              String,
    channel_title        String,
    trending_count       UInt64,
    unique_videos        UInt64,
    total_views          UInt64,
    avg_engagement_rate  Float64,
    top_category         String
)
ENGINE = S3('http://localstack:4566/yt-analytics-bucket/agg_channel_performance/*.parquet', 'test', 'test', 'Parquet');

-- 4. Aggregate table: Time Analysis
CREATE TABLE IF NOT EXISTS youtube_analytics.agg_time_analysis
(
    country              String,
    trending_date        Date,
    day_of_week          String,
    total_videos         UInt64,
    avg_views            Float64,
    top_category         String,
    avg_publish_hour     Float64
)
ENGINE = S3('http://localstack:4566/yt-analytics-bucket/agg_time_analysis/*.parquet', 'test', 'test', 'Parquet');


-- 5. Dimension table: Country information
CREATE TABLE IF NOT EXISTS youtube_analytics.dim_country
(
    country      String,
    country_name String
)
ENGINE = TinyLog;

-- Insert dummy data for 10 countries in dataset
INSERT INTO youtube_analytics.dim_country VALUES 
('US', 'United States'),
('GB', 'United Kingdom'),
('CA', 'Canada'),
('FR', 'France'),
('DE', 'Germany'),
('RU', 'Russia'),
('MX', 'Mexico'),
('KR', 'South Korea'),
('JP', 'Japan'),
('IN', 'India');
