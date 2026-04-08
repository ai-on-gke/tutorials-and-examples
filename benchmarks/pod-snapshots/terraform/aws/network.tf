resource "aws_vpc" "vpc" {
  cidr_block = "10.1.0.0/16"
  region = var.region

  tags = {
    Name = var.name_prefix
  }
}

resource "aws_subnet" "subnet_az1" {
  region = var.region
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.1.16.0/20"
  availability_zone = "${var.region}a"
  
  map_public_ip_on_launch = true
  tags = {
    Name = var.name_prefix
  }
}

resource "aws_subnet" "subnet_az2" {
  region = var.region
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.1.32.0/20"
  availability_zone = "${var.region}c"

  map_public_ip_on_launch = true
  tags = {
    Name = var.name_prefix
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  region = var.region

  tags = {
    Name = "${var.name_prefix}-network-igw"
  }
  depends_on  = [ 
    aws_subnet.subnet_az1,
    aws_subnet.subnet_az2,
  ]
}

resource "aws_route" "internet_access" {
  region = var.region
  route_table_id         = aws_vpc.vpc.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}
