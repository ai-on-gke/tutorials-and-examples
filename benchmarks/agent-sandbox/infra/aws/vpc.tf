resource "aws_vpc" "vpc" {
  cidr_block = "10.1.0.0/16"
  tags = {
    Name = local.network_name
  }
}

resource "aws_subnet" "subnet_az1" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.1.16.0/20"
  availability_zone = "${var.region}a"
  
  map_public_ip_on_launch = true
  tags = {
    Name = local.network_subnet_name
  }
}

resource "aws_subnet" "subnet_az2" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.1.32.0/20"
  availability_zone = "${var.region}b"

  map_public_ip_on_launch = true
  tags = {
    Name = local.network_subnet_name
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${local.network_name}-network-igw"
  }
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.vpc.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}
